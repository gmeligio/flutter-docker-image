## Why

The original framing of this change — "image build logic is pasted into four workflows; extract one reusable workflow" — does not survive contact with the current tree. Research (explore mode, 2026-05-31) established three things:

1. **The four image-build workflows are not near-copies.** `build.yml` (Linux/buildx, fork-split push-or-artifact, SBOM+provenance per p13), `ci.yml` (Linux/buildx, `load:true`, gha cache), `windows.yml` (Windows, raw `docker build` — Buildx has no Windows-container support), and `release.yml` (Linux buildx + Windows raw, three registries) diverge on OS, build engine, output mode, cache backend, registry count, and attestations. Forcing them through one reusable workflow produces an `if:`-forked file that the GitHub community consensus calls a readability *loss*, not a win ([smcleod](https://smcleod.net/2022/11/github-not-so-reusable-actions/), [Octopus](https://octopus.com/devops/github-actions/github-actions-workflow/)). Reusable workflows pay off at *N identical copies*, which this is not.

2. **The biggest readability lever is unused.** No job across the workflow suite sets a `name:`. The Actions checks UI therefore renders bare job ids (`build_image`, `scan_image`, `test_gradle`). GitHub's own docs and community convention say the job *id* stays machine-stable while a human-readable `name:` drives the UI ([Future Studio](https://futurestud.io/tutorials/github-actions-customize-the-job-name)). This is the highest readability-per-effort change available and the prior proposal omitted it entirely.

3. **There is no official GitHub naming standard, but the de-facto convention is clear:** kebab-case for workflow filenames (GitHub's own [`actions/starter-workflows`](https://github.com/actions/starter-workflows/issues/1497) is "mostly kebab-case"; the official actions use kebab-case inputs — [actionlint#450](https://github.com/rhysd/actionlint/issues/450)). The [community thread asking GitHub directly](https://github.com/orgs/community/discussions/39547) never got an official answer, so this is convention-by-example, applied here as the house rule ([[feedback_workflow_naming]]).

This change is therefore re-scoped to capture the **evidence-backed value** — readability via naming + one genuine consolidation — and to **explicitly drop** the speculative reusable-build extraction. It also respects two in-flight changes the original proposal predated: `p13-scout-sbom-provenance` (already rewrote `build.yml`'s build step on `main`) and `p12-symmetric-platform-updates` (mid-refactor of `update_version.yml`'s internals).

## What Changes

- **Rename every job id (the `jobs.<id>:` YAML key) to kebab-case** — used by `needs:`, `github.job`, and branch-protection check pinning — since the user wants repo-wide kebab uniformity for the keys. Every `needs:` reference and every `${{ needs.<id>.outputs.* }}` / `github.job` expression is updated in lockstep within the same commit.
- **Add a `name:` to every job** in every workflow under `.github/workflows/`, as a Title Case verb phrase (e.g. `name: Build and push image`, `name: Scan image`) — the human-readable label shown in the Actions checks UI.
- **Add a top-level `name:` to every workflow file** that lacks one, as a Title Case label for the Actions sidebar (e.g. `name: Build image`).
- **Merge `changelog.yml` + `tag.yml` into `prepare-release.yml`** — a genuine consolidation: two halves of one logical step (write `changelog.md` → create tag) currently linked only by a fragile `paths: [changelog.md]` push trigger. The merged workflow runs `update-changelog` → `create-tag` via `needs:`, preserving the same App-token identity (`VERIFIED_COMMIT_ID/KEY`) so the tag push still triggers `release.yml` and the ruleset bypass actor (tracked by `p10`) stays valid.
- **Rename underscore workflow files to kebab-case**: `update_docs.yml` → `update-docs.yml`, `cleanup_pr_image.yml` → `cleanup-pr-image.yml`. Update each file's top-level `name:` and any cross-references.
- **Defer renaming `update_version.yml`** — it collides with `p12-symmetric-platform-updates`, which is mid-refactor of that file's internals. Renaming it now guarantees a merge conflict. It is renamed in a follow-up after p12 archives.

## Capabilities

### New Capabilities

- `ci-workflow-readability`: the contract that every workflow file and every job SHALL carry human-readable, consistently-cased names — kebab-case filenames and job ids (YAML keys), a Title Case workflow `name:`, and a Title Case job `name:` — so the Actions UI and `ls .github/workflows/` are scannable without opening files. This capability also pins the changelog→tag release-prep step as one workflow (`prepare-release.yml`) with a visible two-job graph.

### Modified Capabilities

_None._ The release-prep merge preserves the `ci-workflow-hardening` properties (App-token push, read-only default permissions, harden-runner) unchanged; the new structural property (one workflow, two jobs) lives in `ci-workflow-readability`.

### Renamed Capabilities

_None._ Capability spec names already use hyphens.

### Removed Capabilities

- The `ci-image-build-reusable` capability proposed by the prior revision of this change is **dropped**. The research found the reusable-build extraction is a net readability loss given the four builds' divergence; it is not pursued. (If ever revisited, scope would be the two genuinely-similar Linux push-builds only — `ci.yml` + `release.yml`'s android job — as a separate change, authored after p13 settles.)

## Impact

- **Affected files**: every workflow under `.github/workflows/` gains job `name:` keys and kebab-case job ids; `changelog.yml` + `tag.yml` → `prepare-release.yml` (2 files → 1); `update_docs.yml` and `cleanup_pr_image.yml` renamed. Net file count: 11 → 10.
- **Behavioral change**: none for image consumers or the release flow. The maintainer sees readable job names in the checks UI and a uniform `ls`.
- **Risk — branch protection check-name pinning goes stale on job-id renames.** Required status checks are pinned by `<workflow> / <job>` name. Renaming job ids/names breaks those pins until repo settings are updated. Mitigation: enumerate every required check name and update repo settings *before* merge ([[user_solo_maintainer]] pins checks; this is an out-of-band Settings change called out in the verify step).
- **Risk — `github.job` references break on id rename.** Mitigation: grep for `github.job` and any `needs.<id>` across all workflows and scripts; update in lockstep within the rename commit.
- **Depends on**: `p7-harden-workflow-permissions` archived (done). Coordinates with `p10-strengthen-branch-protection` (ruleset-as-code references `changelog.yml`/`tag.yml` by name — update those references when merging).
- **Out of scope**: renaming `update_version.yml` (deferred — p12 collision); any reusable-workflow extraction (dropped); image content; release versioning logic.
