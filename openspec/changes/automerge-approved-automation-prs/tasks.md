## 1. Establish the gate before relying on it

- [x] 1.1 Re-read the `main` ruleset at implementation time and confirm `require_code_owner_review` is still `true`, `allowed_merge_methods` is still `["squash"]`, and `allow_auto_merge` is still `true` on the repository — the whole design rests on these three
- [x] 1.2 Confirm the ruleset's `bypass_actors` list is still empty — the design assumes no actor can skip the code-owner gate, and an entry reintroduced here would silently void that assumption
- [x] 1.3 Confirm the `verified-commit` App's installation permissions include `pull requests: write` (it opens PRs, so it should) — `enablePullRequestAutoMerge` needs it. Verified indirectly: the App has authored 14 pull requests, most recently #552; reading `/repos/.../installation` directly requires an App JWT rather than a user token

## 2. Wire auto-merge into the version-bump PR

- [x] 2.1 Add `id: create_pr` to the existing `create-pull-request` step in `compose-and-open-pr`; change nothing else about that step
- [x] 2.2 Add an "Enable auto-merge on the pull request" step after it, using `actions/github-script` with `github-token: ${{ steps.app-token.outputs.token }}` — not `GITHUB_TOKEN`, whose pushes would not trigger `prepare-release.yml`
- [x] 2.3 Fetch the PR's `node_id` via `pulls.get`, then call `enablePullRequestAutoMerge` with `mergeMethod: SQUASH`
- [x] 2.4 Gate the step on `steps.create_pr.outputs.pull-request-number != ''` so it covers both the `created` and `updated` cases and no-ops when nothing was opened
- [x] 2.5 Wrap the mutation in `try`/`catch` reporting through `core.warning`, so a failed enable never fails the job or loses the bump PR
- [x] 2.6 Comment the step with *why* enabling at open time is not merge-on-green: the ruleset's code-owner review is the gate
- [x] 2.7 Leave the job's `permissions:` read-only — the App token carries the write scope
- [x] 2.8 In the same `github-script` step, before enabling auto-merge, detect that the branch is behind `main` and call `pulls.updateBranch` — `strict_required_status_checks_policy: true` means a stale branch blocks the merge that the approval would otherwise complete, and GitHub's auto-merge never updates the branch itself. Determine staleness by comparing the base branch tip (`repos.getBranch` on `main`, or `compare`) against the PR's merge base rather than reading `pull.base.sha`, which is the recorded base commit and does not move as `main` advances
- [x] 2.9 Wrap the update in its own `try`/`catch` reporting through `core.warning` (a conflicted branch cannot be updated), and comment that the update must precede approval because `dismiss_stale_reviews_on_push: true` would dismiss a review it followed
- [x] 2.10 Confirm the update is a no-op when the branch is already current, so no run pushes a needless commit
- [x] 2.11 Order the two calls update-then-enable, and note that `updateBranch` is asynchronous — the subsequent `enablePullRequestAutoMerge` must not depend on the update having landed, since auto-merge simply waits for whatever state the branch reaches
- [x] 2.12 Run `gx lint` and confirm no new finding (no PR-head checkout, no missing permissions, `actions/github-script` already pinned in `gx.toml`)

## 3. Record the guardrails the workflow cannot express

- [x] 3.1 Update `openspec/specs/ci-repo-governance/spec.md` per the delta: the auto-merge requirement now names the ruleset requirements — including code-owner approval — as the merge gate, instead of asserting no approval is required
- [x] 3.2 State `require_code_owner_review: true` as load-bearing: without it, open-time auto-merge degrades into merging unreviewed version bumps on green
- [x] 3.3 State that the merge identity must be one whose pushes trigger workflows, and tie it to the visible consequence — no tag, no release, no published image for the new Flutter version
- [x] 3.4 Add the stale-branch requirement to `ci-repo-governance`: a branch behind `main` cannot merge under `strict_required_status_checks_policy: true`, auto-merge will not update it, and automating the merge click removes the moment the maintainer would have noticed
- [x] 3.5 Update `openspec/specs/ci-workflow-readability/spec.md` per the delta: `prepare-release.yml` has one job (`create-tag`), not the two-job `update-changelog` → `create-tag` graph p10 deleted; re-home the App-token identity clause into that requirement so it is not lost
- [x] 3.6 Update `openspec/specs/flutter-version-update/spec.md` per the delta: the run is weekday-scheduled, not monthly (`cron: '0 0 * * MON-FRI'`)
- [x] 3.7 Update `openspec/specs/windows-version-tracking/spec.md` per the delta: rename the "Monthly upgrade PR…" requirement and its scenario to match the real cadence
- [x] 3.8 On archive, sync the two capability Purpose headers that also say "monthly" (`flutter-version-update:5`, and the context line in `windows-version-tracking`) — prose outside a requirement cannot be carried by a delta

## 4. Verify on the next real bump

- [ ] 4.1 Confirm the workflow log shows auto-merge enabled, and that the PR stays open on green until reviewed
- [ ] 4.2 Approve and confirm the merge lands within seconds, squashed, merged by `verified-commit[bot]`
- [ ] 4.3 Confirm `prepare-release.yml` fires on the resulting push to `main` and creates the tag, and that `release.yml` follows
- [ ] 4.4 Confirm the docs-regeneration push from `update-docs.yml` still lands before any approval, so it never dismisses one
- [ ] 4.5 If the branch went stale behind a Renovate merge, confirm the new update step brought it current and that the checks re-ran — this is the failure mode that would otherwise leave an approved PR silently unmerged

## 5. Wrap up

- [x] 5.1 Open as a draft PR quoting the timings as the evidence for the diagnosis: #552 and #547 (approved, then merged by hand) against #541/#542 and #523/#530 (auto-merge, merged ~2s after approval)
- [x] 5.2 Note in the PR description that this corrects a factual claim in the archived `p10-strengthen-branch-protection` proposal (approvals *are* required for bot-authored PRs)
- [x] 5.3 Record the deferred decision — whether maintainer-authored PRs should get auto-merge too — as a follow-up; it is merge-on-green with no human gate, since GitHub does not accept an author's own approval and the review count floor is `0`
