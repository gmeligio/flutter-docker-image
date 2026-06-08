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

The failure (issue #490) is a **genuinely missing gem**, not merely an activation-context quirk. `representable/json.rb` (pulled in transitively via `googleauth` → `google-apis-core` → `representable`) does `require 'multi_json'` behind a `gem 'multi_json'` activation call, but **`representable`'s gemspec does not declare `multi_json` as a runtime dependency**. Because nothing in fastlane's declared dependency tree depends on `multi_json`, **no installer pulls it in** — neither `bundle add fastlane` nor `gem install fastlane` installs `multi_json` at all. A bare `fastlane` invocation then aborts in `representable/json.rb:1` with `Gem::MissingSpecError: Could not find 'multi_json'`.

**This was verified empirically during implementation** (see Migration Notes): a cold `gem install fastlane` (2.235.0) installed 156 gems including `representable-3.2.0` but **zero `multi_json`**; `fastlane action debug` reproduced the exact #490 stack trace. Installing `multi_json` explicitly made fastlane load successfully.

Why it appears to work for some users under `bundle exec`: their Gemfile transitively includes *other* gems that depend on `multi_json` (e.g. cocoapods / aws-sdk on iOS projects), so `multi_json` ends up in their locked closure by a different edge. It is not fastlane/representable resolving it. This repo's bundle had no such sibling, so `multi_json` was simply never installed.

This is a known fastlane/representable ecosystem issue — undeclared `multi_json` dependency — reproduced verbatim in [actions/runner-images #14186](https://github.com/actions/runner-images/issues/14186) and discussed in [fastlane #21050](https://github.com/fastlane/fastlane/discussions/21050). The standard remedy in those threads is `gem install multi_json` / `bundle add multi_json`.

Two independent problems compound in the current stage: (1) `multi_json` is never installed (the actual #490 break), and (2) bundler indirection adds a manage-vs-invoke layer the image doesn't need. The fix addresses both. Buildcache hides the failure because PR CI reuses the cached `fastlane` layer; only a cold (`--no-cache`) rebuild re-runs resolution and surfaces the break.

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

### Decision: `gem install fastlane multi_json` (drop bundler, install the missing gem explicitly)

Install fastlane *and* the undeclared `multi_json` dependency directly with RubyGems:

```dockerfile
ARG fastlane_version
RUN gem install --no-document --version "$fastlane_version" fastlane multi_json
```

…and delete the bundler scaffolding: the `gem install ... bundler` line, the `BUNDLER_VERSION` env, the `FASTLANE_ROOT` env + `mkdir`, and the `WORKDIR "$FASTLANE_ROOT"`.

**Rationale (two parts):**

1. **`multi_json` must be installed explicitly.** It is the actual #490 fix, verified in-image. Since `representable` does not declare it, no fastlane install pulls it in; the image has to add it directly. This is the upstream-recommended remedy.
2. **Drop bundler.** The image wants a standalone `fastlane` binary on `PATH`, not a project bundle. `gem install` produces exactly that and removes the manage-vs-invoke indirection, so the existing bare-`fastlane` tests in `test/android.yml` are correct by construction (no `bundle exec`, no Gemfile). This is a simplification, but — proven by implementation — **not sufficient on its own**; it must be paired with installing `multi_json`.

`multi_json` is left unpinned, like the rest of fastlane's resolved tree under `gem install`. Adding a hard pin would create a second floating-version maintenance point for an indirect dependency with no corresponding benefit; the base image digest + `fastlane_version` already bound the build.

**Alternatives considered:**

- **C — `gem install fastlane` only (no `multi_json`):** the originally-proposed approach. **Falsified during implementation** — a cold build still failed with the identical `MissingSpecError` because `multi_json` was never installed. The bundler-removal half is kept; the "this alone fixes it" premise was wrong.
- **A′ — `bundle add fastlane multi_json`:** add a declared `multi_json` edge but keep bundler. Fixes the gem-missing half, but retains the bundler indirection and the bare-binstub-vs-bundle mismatch the image doesn't need. The chosen decision is A′ minus bundler.
- **B — run tests via `bundle exec` / `BUNDLE_GEMFILE`:** keep bundler and make invocation re-enter it. Adds harness plumbing (lanes run from `test_app/android`, not `$FASTLANE_ROOT`) for no benefit over removing bundler. Rejected.

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

- **[`multi_json` is an undeclared, future-fragile dependency]** → we install it explicitly because `representable` won't. If a future fastlane/representable release declares it (or drops the `multi_json` require), the explicit install becomes redundant but harmless. Mitigation: a comment in the Dockerfile ties the explicit `multi_json` install to issue #490 so a future maintainer knows why it's there and when it can be removed.
- **[Loss of lockfile reproducibility]** → `gem install` resolves transitive versions at build time rather than from a committed lock. Mitigation: the fastlane version itself stays pinned via `fastlane_version`; the image is already a from-scratch build artifact (no committed lock existed before — `bundle add` generated `Gemfile.lock` inside the image layer, never in the repo), so reproducibility is unchanged in practice and gated by the base image digest + flutter/fastlane pins.
- **[Warm-cache false green]** → the fix can't be trusted from a cached CI run. Mitigation: cold `--no-cache` build verification is a required task step (see Automated Test Strategy). Related: this is instance #2 of the `android.Dockerfile` cold-build drift pattern (sibling: issue #486).
- **[Unrelated apt-pin drift may block a cold build]** → a from-scratch build of `android.Dockerfile` may also hit stale Debian apt pins (#486), unrelated to fastlane, which could obscure verification. **Confirmed during implementation:** the cold build first failed on `curl="8.14.1-2+deb13u2"` (mirror moved to `deb13u3`). Mitigation: bump the drifted pin to reach the fastlane stage (done locally and temporarily for verification only — the curl bump belongs to #486, not this change); treat apt failures as out of scope here.

## Migration Notes

Verification during implementation revised the root-cause model:

- A cold `gem install --no-document --version 2.235.0 fastlane` installed **156 gems including `representable-3.2.0` but no `multi_json`** (0 occurrences in the build log; absent from `gem list`).
- `fastlane action debug` against that image reproduced the exact #490 trace: `representable/json.rb:1 → gem 'multi_json' → Gem::MissingSpecError`.
- `gem install multi_json` in the same image, then `fastlane action debug`, loaded successfully.

Conclusion: `gem install fastlane` alone does **not** fix #490 — `multi_json` must be installed explicitly. The shipped fix is `gem install ... fastlane multi_json`. No rollback concern: the change is confined to one `RUN` line in the `fastlane` stage; reverting restores the prior (broken-on-cold-build) state.
