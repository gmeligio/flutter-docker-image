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

### D1 — A reusable workflow, not a `BUILD_ARGS` environment string

The superseded design collapsed the four `build-args:` blocks to
`build-args: ${{ env.BUILD_ARGS }}`, emitted from a declarative
manifest-path→ARG-name table. Three findings retired it:

| Finding | Consequence for the table shape |
|---|---|
| The blocks are ~16% of the duplication | Removes ~21 of ~135 duplicated lines; the drifted 84% (logins, cache, metadata, attestations) is untouched |
| `windows.git.version` → `git_version` vs `android.Dockerfile:10` `ARG GIT_VERSION` (apt pin) | Table rows for Windows values would reach Linux builds; safe only because ARG names are case-sensitive — an undocumented accident |
| An unmatched `--build-arg` warns, it does not fail | A wrong table partition is silent, not loud |

The reusable workflow removes all three by construction. A workflow that builds
`android.Dockerfile` names only android arguments, so a Windows value cannot
reach it — there is no partition to get wrong, because there is no shared list.

`windows-image.yml` is the in-repo precedent: a `workflow_call` workflow owning a
whole build behind typed inputs. Verified inventory: `.github/actions/` holds one
composite action (`clean-runner-disk`) and `windows-image.yml` is the only
`workflow_call` workflow. This change makes Linux consistent with Windows rather
than introducing a third pattern.

### D2 — Callers declare only genuine differences

Comparing the four legs, they differ in exactly five dimensions, each a
`workflow_call` input:

| Input | Values | Source today |
|---|---|---|
| `target` | `android` \| `web` | `build.yml:155`, `ci.yml:83`, `release.yml:111` |
| `push` | bool | `build.yml:148` vs `ci.yml` `load:` |
| `cache-backend` | `registry` \| `gha` | `build.yml:151-152` vs `ci.yml:107` |
| `attestations` | bool | `build.yml:149-150` only |
| `registries` | which logins run | `release.yml:93` adds Quay; `ci.yml` has no GHCR |

Everything else — the seven `build-args` lines, the Dockerfile path, buildx
setup, metadata — is identical and moves into the workflow. The fork/non-fork
split (`build.yml:143` vs `:172`) becomes `push: false` plus an output-mode input
rather than a duplicated step.

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
| Caller passes a wrong input value | `workflow_call` type checking rejects it at parse time |
| A leg still builds inline | Caught in review; the delta forbids it |

**Not silent, with one exception**: a missing build argument becomes an empty
`ARG`, and every android consumer uses its value in a `RUN` that fails without
it. The exception is the `web` stage (`android.Dockerfile:225`), which declares
none of these arguments — `build.yml:156-157` notes they are inert there — so a
wrong value passed to a `web` build is silently ignored. This is why the
ARG↔build-arg parity check is worth doing, and why it is tracked separately.

## Risks / Trade-offs

**[The build step is no longer inline in the caller]** → A reader of `ci.yml` sees
a call, not a build. Mitigated by this being the repository's own established
pattern (`windows-image.yml`), so the indirection is one a maintainer already
navigates, not a new concept.

**[Refactor touches three workflow files plus a new one]** → Unavoidable, since
the point is removing duplication. Bounded by the per-leg command-line check.

**[`workflow_call` output plumbing]** → `build.yml:59-62` exposes job outputs to
`test-image`/`scan-image`. Reusable workflows support outputs, but they must be
promoted from step → job → workflow explicitly, and under a matrix the value is
that of the last successful run that set one. `build.yml` builds a matrix of
targets, so outputs must be keyed per target or the callers restructured to
consume them per leg. This is the main implementation risk and is called out as
its own task.

## Migration Plan

1. Add `linux-image.yml` reproducing the `build.yml` push path exactly, plus the
   emitter's fail-loud and logging changes. Nothing calls it yet — inert and
   independently revertable.
2. Switch `ci.yml` first: it is the simplest leg (no GHCR, no attestations, `gha`
   cache) and its failure is cheapest to observe. Verify its command line against
   the baseline.
3. Switch `build.yml` (both paths, including matrix output plumbing), then
   `release.yml` (Quay, `--debug`). Verify each against its baseline.
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
