## Context

The `fastlane` stage of `android.Dockerfile` installs fastlane into a per-project bundle:

```dockerfile
RUN gem install --no-document --version "$BUNDLER_VERSION" bundler
ENV FASTLANE_ROOT="$SDK_ROOT/fastlane"
RUN mkdir -p "$FASTLANE_ROOT"
WORKDIR "$FASTLANE_ROOT"
RUN bundle init && bundle add --version "$fastlane_version" fastlane
```

`GEM_HOME` and `GEM_PATH` both point at `$SDK_ROOT/ruby`, and `$GEM_HOME/bin` is on `PATH`, so `bundle add` does install fastlane and its ~165 transitive gems into `GEM_HOME` and drops a `fastlane` binstub there.

The failure (issue #490) is not a missing gem on disk — it's a missing *dependency declaration*. `representable/json.rb` (pulled in transitively via `googleauth` → `google-apis-core` → `representable`) does `require 'multi_json'` behind a `gem 'multi_json'` activation call, but **`representable`'s gemspec does not declare `multi_json` as a runtime dependency**. Under `bundle exec`, bundler activates the entire locked closure up front, so `multi_json` is already on the load path and the bare `gem` call is satisfied. Under a **bare binstub** (how `test/android.yml` invokes it — `fastlane hello` from `test_app/android`, no `bundle exec`), RubyGems activates lazily and strictly by declared dependency edges; with no edge to `multi_json`, `gem 'multi_json'` raises `Gem::MissingSpecError` even though the gem sits in `GEM_HOME/gems`.

This is a known fastlane/representable ecosystem issue, reproduced verbatim in [actions/runner-images #14186](https://github.com/actions/runner-images/issues/14186) and discussed in [fastlane #21050](https://github.com/fastlane/fastlane/discussions/21050).

The mismatch is structural: gems are **managed by bundler** but **invoked through RubyGems activation**. Buildcache hides it because PR CI reuses the cached `fastlane` layer; only a cold (`--no-cache`) rebuild re-runs resolution and surfaces the break.

## Goals / Non-Goals

**Goals:**
- A bare `fastlane` invocation in the `flutter-android` image resolves its full gem closure and runs lanes, from any working directory, without `bundle exec`.
- Fix the root cause (the manage-vs-invoke mismatch), not just the `multi_json` symptom.
- Keep the change minimal and the fastlane version still pinned via `config/version.json` → `fastlane_version` build arg.
- Net simplification of the Dockerfile stage.

**Non-Goals:**
- Changing how `test/android.yml` invokes fastlane.
- Adopting a project Gemfile / lockfile workflow inside the image.
- Touching the `flutter`, `web`, or `windows` images, or any non-fastlane part of `android.Dockerfile`.
- Upgrading the fastlane version itself.

## Decisions

### Decision: Replace `bundle add` with `gem install fastlane`

Install fastlane with RubyGems directly:

```dockerfile
ARG fastlane_version
RUN gem install --no-document --version "$fastlane_version" fastlane
```

…and delete the bundler scaffolding: the `gem install ... bundler` line, the `BUNDLER_VERSION` env, the `FASTLANE_ROOT` env + `mkdir`, and the `WORKDIR "$FASTLANE_ROOT"`.

**Rationale:** `gem install` builds and installs the closure that RubyGems' *own* lazy activation expects — the binstub it generates is runnable standalone by design. The repo never wanted a project bundle here; it wants a `fastlane` binary on `PATH`. Removing bundler removes the mismatch at its source, so the existing bare-`fastlane` tests become correct by construction with no further edits.

**Alternatives considered:**

- **A — `bundle add fastlane multi_json`:** add a declared `multi_json` edge to the Gemfile. This is the literal upstream workaround and a 1-line diff, but it treats the symptom: any *other* undeclared transitive (rare, but the same class of bug) would recur, and it pins a gem the repo doesn't directly use. Rejected in favor of fixing the cause.
- **B — run tests via `bundle exec` / `BUNDLE_GEMFILE`:** keep bundler and make invocation re-enter it. Robust, but the lanes run from `test_app/android` (not `$FASTLANE_ROOT`), so it needs `BUNDLE_GEMFILE` plumbing or a copied Gemfile, adding moving parts to the test harness for no benefit over removing bundler. Rejected.

### Decision: Preserve all surrounding env unchanged

`GEM_HOME`, `GEM_PATH`, `PATH` (with `$GEM_HOME/bin`), and the `FASTLANE_OPT_OUT_USAGE` / `FASTLANE_SKIP_UPDATE_CHECK` / `FASTLANE_HIDE_CHANGELOG` vars stay exactly as they are. The binstub already lands in `$GEM_HOME/bin`, which is already on `PATH`, so the "fastlane on PATH" and "analytics opted out" behaviors are retained without edits.

## Automated Test Strategy

The critical path is the existing `test/android.yml` container-structure-test suite, run by the `Test image (flutter-android)` CI job:

- **"Fastlane can run lanes"** — `fastlane hello` from `test_app/android`; exit 0. This is the regression that #490 fails.
- **"Fastlane usage is opted-out"** — `fastlane action debug`; output excludes "Sending anonymous analytics information".

No new test infrastructure is required — both tests already exist and already exercise the bare-binstub path that was broken. The one essential addition to the *process* (not the harness): verification must run against a **cold (`--no-cache`) build**, because buildcache masks the failure. `script/docker_build_android.sh` builds the `android` target locally and is the vehicle for the cold-build check; the `tasks.md` verification step calls this out explicitly. A green PR with warm cache is not sufficient proof.

## Observability

Failures surface loudly and non-silently:

- A broken gem closure makes the `fastlane` binstub exit non-zero with a `Gem::MissingSpecError` stack trace on stderr (exactly how #490 was diagnosed). container-structure-test reports the non-zero exit and fails the `Test image (flutter-android)` job — no silent pass is possible for the "can run lanes" test.
- The opt-out test asserts on output content, so a regression in analytics suppression also fails loudly rather than silently phoning home.
- Because the failure mode is cold-build-only, the residual risk is a *false green* on warm-cache CI — mitigated by the mandated `--no-cache` verification in `tasks.md`, not by logging.

## Risks / Trade-offs

- **[Loss of lockfile reproducibility]** → `gem install` resolves transitive versions at build time rather than from a committed lock. Mitigation: the fastlane version itself stays pinned via `fastlane_version`; the image is already a from-scratch build artifact (no committed lock existed before — `bundle add` generated `Gemfile.lock` inside the image layer, never in the repo), so reproducibility is unchanged in practice and gated by the base image digest + flutter/fastlane pins.
- **[Warm-cache false green]** → the fix can't be trusted from a cached CI run. Mitigation: cold `--no-cache` build verification is a required task step (see Automated Test Strategy). Related: this is instance #2 of the `android.Dockerfile` cold-build drift pattern (sibling: issue #486).
- **[Unrelated apt-pin drift may block a cold build]** → a from-scratch build of `android.Dockerfile` may also hit stale Debian apt pins (#486), unrelated to fastlane, which could obscure verification. Mitigation: verify on a base that already builds cold (or land after/with #486); treat an apt failure as out of scope for this change.
