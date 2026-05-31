## Context

`.github/workflows/` currently holds 11 workflows. Two readability problems and one genuine redundancy remain after p7 (hardening):

- **No job carries a `name:`.** The Actions checks UI and branch-protection check list render bare job ids (`build_image`, `scan_image`, `test_gradle`, `release_android`). The id is the only label a reviewer sees.
- **Naming is inconsistent.** Filenames mix kebab (`build.yml`, `cleanup_pr_image.yml`) and snake (`update_version.yml`). Job ids are uniformly snake_case.
- **The release-prep chain is two file-push-linked workflows.** `changelog.yml` (writes `changelog.md` on `config/version.json` change) and `tag.yml` (creates a tag on `changelog.md` change) are two halves of one logical step, coupled only by a `paths:` trigger — fragile and split across two run logs.

The prior revision of this change proposed extracting one reusable `build-image.yml` for all four image builds. Research (explore mode, 2026-05-31) found the four builds diverge on six axes (OS, build engine, output, cache, registries, attestations) and that p13 already rewrote `build.yml`'s build step on `main`. A single parametrized reusable workflow would be an `if:`-forked file — the anti-pattern the community warns against. That extraction is dropped.

Constraints:
- Solo maintainer; required status checks are pinned by name in the ruleset ([[user_solo_maintainer]]). Renaming job ids/names is a breaking change for those pins.
- `p12-symmetric-platform-updates` is mid-refactor of `update_version.yml`'s internals. This change renames that file (maintainer's call) and edits its job ids; p12's artifacts still name the old file and will reconcile on its rebase.
- `p10-strengthen-branch-protection` captures the ruleset as code and references `changelog.yml`/`tag.yml` by name.

## Goals / Non-Goals

**Goals:**
- Every workflow file and job is readable and consistently kebab-cased: kebab filenames, kebab job ids, Title Case workflow `name:`, kebab-case job `name:`.
- The changelog→tag step is one workflow with a visible two-job graph.
- Zero behavioral change for image consumers and the release flow.

**Non-Goals:**
- Extracting a reusable image-build workflow (dropped — see Context).
- Changing image content, cache backends, registry targets, or release versioning logic.
- Raising any Scorecard finding (this is readability/consolidation, not hardening).

## Decisions

**D1 — Job ids become kebab-case, not just the display `name:`.** The user confirmed repo-wide kebab uniformity. *Alternative considered:* keep snake_case ids (valid per GitHub docs, zero check-pinning churn) and add only a kebab `name:`. Rejected because the user explicitly wants ids kebab too, and a half-measure (kebab name over snake id) leaves the `needs:` graph and `github.job` reads inconsistent with the stated convention. The cost — updating pinned checks once — is paid deliberately and called out in tasks.

**D2 — The job *id* (YAML key) is kebab-case; the job `name:` display label is Title Case.** *Rationale:* the user wants the YAML keys kebab-cased for repo-wide uniformity (`build-image:`, `scan-image:`, `test-image:`), while the `name:` follows the community "Verb description" pattern in Title Case (`Build and push image`, `Scan image`) ([Future Studio](https://futurestud.io/tutorials/github-actions-customize-the-job-name)). The top-level workflow `name:` is likewise Title Case (`Build image`, `Prepare release`), matching existing `name:`-bearing workflows. The key is the machine identifier; the `name:` is the human label — two layers, two audiences.

**D3 — `prepare-release.yml` lifts the two existing jobs verbatim, only re-wiring the trigger.** `update-changelog` is the body of today's `changelog.yml` `changelog` job; `create-tag` is today's `tag.yml` `create_git_tag` job with `needs: update-changelog` replacing the `paths: [changelog.md]` push trigger. *Alternative considered:* collapse into one job. Rejected — the two-job graph makes "changelog committed but tag failed" visible and preserves the `needs:` skip semantic (no orphan tag without a changelog commit). The App-token (`VERIFIED_COMMIT_ID/KEY`) and commit identity are unchanged, so the tag push still triggers `release.yml` and the p10 ruleset bypass actor stays valid.

**D4 — Renames land in a dedicated commit, separate from the name-adding edits.** So `git log --follow` traces `update_docs.yml` → `update-docs.yml` cleanly. The `changelog.yml`+`tag.yml`→`prepare-release.yml` merge is its own commit too (a delete-two-add-one, not a rename git can follow).

## Risks / Trade-offs

- **Pinned required-status-checks go stale when job ids/names change** → enumerate every required check (ruleset `1959230` / Settings → Branches) and update the pins *before* merge; otherwise the post-merge run is blocked. Tracked as an explicit pre-merge task.
- **`github.job` or `needs.<id>` left referencing an old id** → grep all of `.github/workflows/` and `script/` for `github.job` and `needs\.` before committing the rename; CI's own YAML parse + a dry `workflow_dispatch` surfaces any miss.
- **`prepare-release.yml` trigger regression silently breaks the release chain** → the merged trigger is `push: { branches: [main], paths: [config/version.json] }` (today's `changelog.yml` trigger), NOT the `changelog.md` trigger (today's `tag.yml`); the `needs:` edge replaces that second trigger. Verified by a no-op `config/version.json` edit on a branch + `workflow_dispatch`.
- **p10 ruleset-as-code references the deleted filenames** → coordinate: update `.github/rulesets/main.json` comments and any check-name list in the same PR or immediately after.

## Migration Plan

1. Commit A: add workflow `name:` + job `name:` keys (no id changes) — safe, no pin breakage.
2. Commit B: rename job ids to kebab-case + update all `needs:`/`github.job` refs.
3. Commit C: merge `changelog.yml`+`tag.yml` → `prepare-release.yml`, delete the two.
4. Commit D: `git mv` `update_docs.yml`, `cleanup_pr_image.yml` to kebab; update `name:` and refs.
5. Out-of-band before merge: update pinned required-status-check names in repo settings + p10 ruleset file.
6. Rollback: revert the PR; pinned-check names must be reverted in settings too (manual). Low blast radius — no image or release-logic change.

## Automated Test Strategy

There is no application code path here; verification is at the workflow level.
- **Static**: `gx lint` must stay green (no action-pin drift introduced); YAML must parse (GitHub rejects invalid workflow files on push). A repo-wide grep asserts no `_` in any `.github/workflows/*.yml` filename, and no dangling `needs.<old_id>` / `github.job` reference.
- **Dynamic (critical path)**: in the draft PR, `workflow_dispatch` `prepare-release.yml` against a branch with a no-op `config/version.json` edit and assert the job graph runs `update-changelog` → `create-tag` and the resulting tag triggers `release.yml`. `workflow_dispatch` each renamed workflow once to confirm it still runs under its new filename.
- **No new test infrastructure** is introduced.

## Observability

- **Failure surfacing**: every change here is visible in the Actions UI. A broken `needs:` reference fails the workflow's YAML validation immediately on push (loud, not silent). A stale pinned check name surfaces as a "waiting for status" block on the merge — visible, not silent, though it requires the maintainer to recognize the cause (called out in tasks).
- **The one silent-failure risk** is the `prepare-release.yml` trigger: if the `paths:` filter is mis-copied, a version bump would merge without producing a tag and *nothing would error*. Mitigation is the explicit dynamic verify step (above) plus keeping the trigger byte-identical to today's `changelog.yml` trigger.
- **Logging**: the merged `prepare-release.yml` run now shows both steps in one log/graph instead of two disconnected runs — strictly more observable than today.

## Open Questions

_None._ The job-id casing question (kebab vs keep-snake) was resolved by the user: kebab-case ids. `update_version.yml` is renamed in this change at the maintainer's request (the earlier p12-collision deferral was reversed).
