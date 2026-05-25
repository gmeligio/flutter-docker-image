## Why

After p7 (hardening) and p8 (composites) land, two structural redundancies in `.github/workflows/` remain:

1. **Image build logic lives in four workflows** with the same shape: `build.yml` (PR/dispatch — 380 lines), `ci.yml` (push to main — 83 lines), `windows.yml` (PR/dispatch — 70 lines), `release.yml` (push tags — 277 lines). All four call `docker/metadata-action` → `docker/build-push-action` → `container-structure-test-action` (or its Windows equivalent) with subtly different inputs. The Linux flavor (build/ci/release) and the Windows flavor (windows/release) each have a single semantic build that has been pasted into multiple files.
2. **The release-prep chain spans three workflows** linked by file/tag push events: `changelog.yml` (writes `changelog.md` when `config/version.json` changes) → `tag.yml` (creates a tag when `changelog.md` changes) → `release.yml` (builds and publishes when a tag is pushed). The chain is fragile (one disabled workflow breaks the whole chain), slow (three sequential job startups), and split across files that are read independently.

This change introduces a **reusable workflow** for the image build and **merges the changelog+tag pair** into a single workflow. It also takes the opportunity to **rename every underscore-named workflow to kebab-case**, fixing the convention drift before more files accumulate.

## What Changes

- **Add reusable workflow `.github/workflows/build-image.yml`** with `on: workflow_call` and inputs covering: `runner-os` (`ubuntu-24.04` | `windows-2025`), `dockerfile`, `image-name`, `push-to-registries` (boolean), `cache-mode` (`gha` | `registry`), `tag-prefix`. The reusable workflow encapsulates: harden-runner, `setup-build-context` (from p8), `docker-registry-login` (from p8), `docker/metadata-action`, `docker/build-push-action`, `container-structure-test-action`, optional `docker/scout-action`. Its single job emits an output with the built image's digest.
- **Rewrite `build.yml`, `ci.yml`, `windows.yml`, `release.yml`** as thin callers of `build-image.yml`. Each becomes ~30-50 lines: trigger, concurrency, and `uses: ./.github/workflows/build-image.yml` with the appropriate inputs/secrets.
- **Merge `changelog.yml` + `tag.yml` into `prepare-release.yml`** that, on push to `main` with `config/version.json` changed, runs two sequential jobs: `update-changelog` (writes `changelog.md` and commits) → `create-tag` (creates the tag and pushes it). The tag push still triggers `release.yml` exactly as today; this collapses the three-workflow chain to two.
- **Rename underscore workflows to kebab-case** (no leading underscore, no `_` anywhere): `update_version.yml` → `update-version.yml`, `update_docs.yml` → `update-docs.yml`, `cleanup_pr_image.yml` → `cleanup-pr-image.yml`. Updated workflow names also update the `name:` key inside each file.
- **Delete** the now-empty `changelog.yml` and `tag.yml` files (their content moves into `prepare-release.yml`). Update any external references (README badges, branch protection check names) that named the old workflows.

## Capabilities

### New Capabilities

- `ci-image-build-reusable`: the contract that `build-image.yml` SHALL satisfy as a reusable workflow — inputs accepted, outputs emitted, jobs/steps composed, and the rule that every caller (PR build, CI build, Windows build, release build) goes through it instead of inlining its own.

### Modified Capabilities

- `ci-image-build-cache`: clarify that the cache-mode selection (GHA cache vs registry cache) is an input to the reusable workflow, not duplicated across caller workflows.
- `ci-image-handoff`: clarify that the handoff tag computation is encapsulated in the reusable workflow, not in `build.yml`'s inline `run:` blocks.
- `ci-parallel-image-validation`: clarify that the parallel validation matrix now invokes the reusable workflow per matrix cell.
- `windows-image-release`: clarify that the Windows release path is a caller of the reusable workflow with `runner-os: windows-2025`.

### Renamed Capabilities

_None._ Capability names already use hyphens; this change renames only workflow files, not specs.

## Impact

- **Affected files**: 4 image-build workflows rewritten as thin callers; 1 new reusable workflow; 2 workflows merged into 1; 3 workflows renamed. Net file count: 11 → 9 in `.github/workflows/`.
- **Behavioral change**: image consumers see no difference. The maintainer sees the workflow list shrink by 2 files and each caller drop to under 50 lines. Branch protection rules that pin a check by `name:` MUST be updated (this is an out-of-band repo settings change called out in the verification step).
- **Risk**: this is the largest refactor of the three. Mitigation: ship behind a draft PR that runs each caller via `workflow_dispatch` and compares the built image digest against `main`. Renames go in a separate commit within the PR so `git log --follow` works cleanly.
- **Risk**: branch protection check-name pinning silently goes stale on renamed workflows. Mitigation: enumerate every check name in the verification step and update the repo settings before merging.
- **Depends on**: `p7-harden-workflow-permissions` archived, `p8-extract-workflow-composites` archived. p8's composites are the building blocks of the reusable workflow's body.
- **Out of scope**: changes to image content; changes to release versioning logic; changes to the cleanup-pr-image trigger semantics (rename only); changes to `update-version.yml` internals (rename only — its 421-line refactor is a separate future change).
