## Context

Four Linux build legs duplicate a ~45-line build step and have drifted in the
parts that are not mechanically copied. `windows-image.yml:7-27` already
demonstrates the boundary this change adopts. Full findings in `./research.md`;
the originating observation is `../loud-deb-pin-resolution/research.md` F10,
whose proposed shape this change supersedes.

## Goals / Non-Goals

**Goals:**

- The Linux build procedure exists once; the four legs cannot drift.
- A caller declares only how its leg legitimately differs.
- Per-ARG Docker layer-cache granularity is preserved exactly.
- Zero change to emitted build-argument names and values.
- A manifest path that does not resolve fails the step, not the build.

**Non-Goals:**

- Renaming any build argument.
- The Windows image build — `windows-image.yml` already has this boundary, and
  Buildx does not support Windows containers (`windows-image.yml:123`).
- Moving the nine Renovate-owned apt pins into `config/version.json`.
- Checking that build-args passed match `ARG`s declared — issue #539.

## Decisions

### D1 — A composite action, not a `BUILD_ARGS` string and not a reusable workflow

The superseded design collapsed the four `build-args:` blocks to
`build-args: ${{ env.BUILD_ARGS }}`, emitted from a declarative
manifest-path→ARG-name table. Three findings retired it:

| Finding | Consequence for the table shape |
|---|---|
| The blocks are ~16% of the duplication | Removes ~21 of ~135 duplicated lines; the drifted 84% (logins, cache, metadata, attestations) is untouched |
| `windows.git.version` → `git_version` vs `android.Dockerfile:10` `ARG GIT_VERSION` (apt pin) | Table rows for Windows values would reach Linux builds; safe only because ARG names are case-sensitive — an undocumented accident |
| An unmatched `--build-arg` warns, it does not fail | A wrong table partition is silent, not loud |

A single callable unit removes all three by construction. Whatever builds
`android.Dockerfile` names only android arguments, so a Windows value cannot
reach it — there is no partition to get wrong, because there is no shared list.

**A reusable workflow was the first choice here and is wrong.** Reading the four
legs in full — not just their `build-args:` blocks — showed that a
`workflow_call` workflow is a separate *job*, and all four Linux legs depend on
job-local state that cannot cross a job boundary:

| Obstacle | Evidence |
|---|---|
| `ci.yml` builds with `load: true` into the local Docker daemon and tests it in the next step of the same job | `ci.yml:74-94` — a locally-loaded image does not survive a job boundary, so the call could not return it |
| `ci.yml` has no separate build job to replace | build and `container-structure-test` are steps of one `test-image` job |
| `build.yml` interleaves the build with fork-handoff machinery sharing `steps.handoff`/`steps.metadata` | `build.yml:109-122` (handoff tag), `:195-201` (re-tag), `:203-216` (save + upload) |

A composite action runs **inside** the calling job, so the local daemon,
`steps.metadata`, and the fork handoff keep working untouched. It removes the
same duplication without restructuring any job graph.

`.github/actions/clean-runner-disk` is the in-repo precedent, used by all four
Linux legs already (`build.yml:87`, `ci.yml:60`, plus `windows-image.yml:51`).
`windows-image.yml` remains a reusable workflow because the Windows path has no
equivalent constraint — it is one job that builds, pushes, and tests, with
nothing to hand across a boundary.

### D2 — Callers declare only genuine differences

The composite action owns the `docker/build-push-action` invocation — the seven
`build-args` lines, `file: android.Dockerfile`, `labels`, and `tags`. Callers
pass only what genuinely differs:

| Input | Values | Source today |
|---|---|---|
| `target` | `android` \| `web` | `build.yml:155`, `ci.yml:83`, `release.yml:111` |
| `cache-from` / `cache-to` | passed through verbatim | see below |
| `push` / `load` / `outputs` | output mode | `build.yml:148` vs `:176` vs `ci.yml:78` |
| `sbom` / `provenance` | attestations | `build.yml:149-150` only |
| `tags` / `labels` | from the caller's own `metadata` step | each leg's `steps.metadata` |

**Cache is passed through, not enumerated.** The four legs use three different
shapes, so a `registry|gha` enum cannot express them:

| Leg | cache |
|---|---|
| `build.yml` push/fork | `type=registry,ref=ghcr.io/<owner>/<name>:buildcache` |
| `ci.yml` | `type=gha` (unscoped) |
| `release.yml` | `type=gha,scope=<name>` (`release.yml:107-108`) |

Both the registry ref and the gha scope vary per image, so the value is
caller-specific either way. Passing the string through keeps each leg's current
behaviour exactly and avoids an enum that would need a ref/scope parameter to be
useful — at which point it is just the string again.

Registry logins, buildx setup, and `metadata-action` stay in the callers. They
run before the build, differ per leg (`release.yml:93` adds Quay; `ci.yml` has no
GHCR; `build.yml` gates both on non-fork), and — unlike the build step — are not
where the drift risk that motivates this change lives.

**Layer caching is the constraint that shapes the build-args handling.** The
tempting simplification — one JSON build-arg, or `COPY config/version.json` into
the build — would make any version change invalidate every layer below it. Builds
run 15–25 minutes and lean on registry buildcache (`build.yml:151-152`), so a
Fastlane bump must not re-clone the Flutter SDK. The workflow emits the same N
discrete `--build-arg` flags BuildKit sees today. Only *location* changes.

### D3 — The emitter keeps its exports and gains a failure mode

`setEnvironmentVariables.js` continues to export individually. Its exports are
read beyond the build step: `FLUTTER_VERSION` by tagging and test steps,
`IMAGE_REPOSITORY_PATH` (composed from `GITHUB_REPOSITORY_OWNER`, not
manifest-derived) by metadata, and the `VS_*`/`GIT_VERSION` group by
`windows-image.yml:137-146`. Three of the seven call sites
(`release.yml:208`, `prepare-release.yml:52`, `update-version.yml:390`) consume
exactly one variable, so nothing is gained by restructuring the emitter here.

Two changes are in scope because they are cheap and prevent silent failure:

1. A table row referencing an unresolvable manifest path throws a named error
   rather than exporting `undefined`.
2. The resolved values are logged, so a job log shows what was passed.

The over-broad export surface — twelve variables delivered to call sites needing
one — is a real defect but belongs to the provenance/ownership concern
(`./research.md` F3), not here. This change does not worsen it.

## Automated Test Strategy

The change is a pure refactor with a cheap, near-complete check: **the resolved
`docker buildx build` command line must be equivalent per leg before and after.**

1. Capture the current command line from each of the four legs in a recent CI run
   (run `31194164846` shows the present form).
2. After the refactor, compare the same lines from a PR run — same args, same
   values, same target, same cache and output flags.

Because no name or value changes, that diff covers the build-args surface
exhaustively. The dimensions it does *not* cover — which registries were logged
into, whether attestations were produced — are visible as separate steps in the
job log and are asserted by the existing `scan-image` leg. `container-structure-test`
against `test/android.yml` remains the backstop that the built image is correct.

## Observability

| Failure | Surfaces as |
|---|---|
| Manifest path unresolvable | Emitter throws → step fails before any build starts |
| A build-arg the Dockerfile needs is absent | Empty `ARG` → build fails at the consuming `RUN` (android stages) |
| A build-arg no `ARG` declares is passed | BuildKit **warning only** — does not fail |
| Caller omits a required input | Composite action input validation fails the step |
| A leg still builds inline | Caught in review; the delta forbids it |

**Not silent, with one exception**: a missing build argument becomes an empty
`ARG`, and every android consumer uses its value in a `RUN` that fails without
it. The exception is the `web` stage (`android.Dockerfile:225`), which declares
none of these arguments — `build.yml:156-157` notes they are inert there — so a
wrong value passed to a `web` build is silently ignored. This is why the
ARG↔build-arg parity check is worth doing, and why it is tracked separately.

## Risks / Trade-offs

**[The build step is no longer inline in the caller]** → A reader of `ci.yml` sees
a `uses:`, not a `build-args:` list. Mitigated by this being the repository's own
established pattern (`.github/actions/clean-runner-disk`, already used by every
Linux leg), so the indirection is one a maintainer already navigates.

**[Refactor touches three workflow files plus a new one]** → Unavoidable, since
the point is removing duplication. Bounded by the per-leg command-line check.

**[A composite action cannot gate on `if:` at job level]** → Not a problem here:
`build.yml`'s fork/non-fork gate stays on the caller's step
(`build.yml:143`/`:172`), which is where it already lives. The action is invoked
by whichever step's condition matches.

**[Secrets are not implicitly available]** → Composite actions cannot read
`secrets` directly. Not a problem here either: all registry logins stay in the
callers (D2), so the action never needs a credential.

## Migration Plan

1. Add `.github/actions/build-linux-image` plus the emitter's fail-loud and
   logging changes. Nothing uses it yet — inert and independently revertable.
2. Switch `ci.yml` first: it is the simplest leg (one build step, no fork gate)
   and its failure is cheapest to observe. Verify against the baseline.
3. Switch `build.yml` (both push and fork steps), then `release.yml`. Verify each
   against its baseline.
4. Confirm no workflow still contains an inline `build-args:` block for
   `android.Dockerfile`.

Rollback: each step is a separate commit; every step after 1 changes exactly one
leg, so a regression is isolated to the leg just switched.

## Open Questions

1. **Should the drifted settings be preserved or unified?** `release.yml:78`'s
   `buildkitd-flags: --debug` and `ci.yml`'s missing GHCR login are drift, but it
   is not established whether each is intentional. The migration preserves
   current per-leg behaviour via inputs; deciding whether `--debug` should apply
   everywhere or nowhere is a follow-up, not a blocker.
