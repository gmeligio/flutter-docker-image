## Why

Four Linux build legs each restate the same ~45-line build step: harden-runner,
checkout, manifest read, disk cleanup, buildx setup, registry logins, metadata,
and `docker/build-push-action` with seven hand-typed `build-args` lines
(`build.yml:142-165` push path, `build.yml:171-188` fork path, `ci.yml:74-91`,
`release.yml:100-121`).

They are kept in sync by hand, and they have already drifted: `release.yml:78`
carries `buildkitd-flags: --debug` that no other leg has, `release.yml:93` adds a
Quay login, `ci.yml` has no GHCR login, and only `build.yml:149-150` requests
attestations. The `build-args:` blocks are, ironically, the one section still
byte-identical across all four — so deduplicating only those would address the
16% that has *not* drifted while leaving the 84% that has.

The repository already factors shared build steps this way. `windows-image.yml:7-27`
is a reusable workflow owning the entire Windows build, and
`.github/actions/clean-runner-disk` is a composite action every Linux leg already
uses (`build.yml:87`, `ci.yml:60`). The Linux build step itself is the one piece
of shared work with no such boundary.

Relevance gate: this changes observable behaviour a CI engineer depends on —
whether the four build legs agree about how an image is built, and whether a
change to the build procedure reaches every leg. Drift between legs means the
image validated in CI is not built the same way as the image released.

## What Changes

- A new composite action `.github/actions/build-linux-image` owns the
  `docker/build-push-action` invocation — including the seven `build-args` lines,
  which exist **once**.
- `build.yml` (both paths), `ci.yml`, and `release.yml` use it, passing only what
  genuinely differs: target, cache configuration, output mode, attestations, and
  the tags/labels from their own metadata step.
- `script/setEnvironmentVariables.js` fails loudly when a manifest path does not
  resolve, instead of exporting `undefined`, and logs what it resolved.

Explicitly **not** a `BUILD_ARGS` string passed through the environment. An
earlier revision of this change proposed collapsing the four blocks to
`build-args: ${{ env.BUILD_ARGS }}` emitted from a declarative table. That shape
is superseded: it removed ~21 of ~135 duplicated lines, made four call sites
opaque, and — because `windows.git.version` and the Debian `git` apt pin at
`android.Dockerfile:10` share the name `GIT_VERSION` — depended for its safety on
an undocumented casing convention. A Linux-only callable unit simply never names
`git_version`, so the hazard cannot arise.

Also **not** a reusable workflow, which was this change's first shape. A
`workflow_call` workflow is a separate job, and every Linux leg depends on
job-local state that cannot cross a job boundary: `ci.yml` builds with
`load: true` into the local Docker daemon and tests it in the next step
(`ci.yml:74-94`), and `build.yml` interleaves the build with fork-handoff
machinery sharing `steps.handoff` and `steps.metadata` (`build.yml:109-122`,
`:195-216`). A composite action runs inside the calling job, so none of that
needs restructuring. `windows-image.yml` stays a reusable workflow because the
Windows path has no equivalent constraint.

Not in scope, and stated so it is not mistaken for an omission: the Windows image
build (`windows-image.yml` already has this boundary; Buildx does not support
Windows containers, per `windows-image.yml:123`); renaming any build argument;
moving the nine Renovate-owned apt pins into the manifest; and verifying that the
build-args passed match the `ARG`s declared — that is a separate concern tracked
in issue #539, since it is correct independently of this change's shape.

## Capabilities

### New Capabilities

- `linux-image-build-boundary`: the Linux image build as a single callable unit —
  what a caller declares, what the unit owns, and why manifest values reach the
  build through it rather than through a shared environment namespace.

## Impact

**Added**: `.github/actions/build-linux-image/action.yml`.

**Modified**: `.github/workflows/build.yml`, `ci.yml`, `release.yml` (build steps
become `uses:`); `script/setEnvironmentVariables.js` (fail-loud + logging).

**Unchanged by design**: every build-argument name and value; every `ARG`
declaration in `android.Dockerfile` and `windows.Dockerfile`;
`config/version.json`; `windows-image.yml`.

**Verification**: the resolved `docker buildx build` command line must be
equivalent per leg before and after — same args, same values, same target, same
cache and output behaviour. Because no name or value changes, diffing that line
against a pre-refactor baseline is a complete check. `container-structure-test`
against `test/android.yml` remains the backstop.

**Risk**: a composite action adds a layer between a caller and its build step, so
a reader of `ci.yml` no longer sees the build arguments inline. Mitigated by this
being the repository's established pattern for shared steps —
`.github/actions/clean-runner-disk`, already used by every Linux leg — rather
than a new idiom. Because the action runs inside the calling job, no job outputs,
matrix plumbing, or handoff logic changes.

**Correction of record**: an earlier revision of this proposal claimed
`android.java.version` "sits in the manifest but reaches no build." That was true
when written and is now false — commit `0c9b3ff` (PR #537) wired it end to end:
exported at `setEnvironmentVariables.js:34`, passed at `build.yml:161,184`,
`ci.yml:87`, `release.yml:117`, declared at `android.Dockerfile:137`, consumed at
`:139` and `:162`, asserted at `config/android.cue:60`. There are therefore
**seven** manifest-derived build arguments per block, not six. That defect was
fixed without this change, which is why this change now rests on build-step drift
rather than on authoring cost.
