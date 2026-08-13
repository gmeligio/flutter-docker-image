## 1. Establish the gate before relying on it

- [ ] 1.1 Re-read the `main` ruleset at implementation time and confirm `require_code_owner_review` is still `true`, `allowed_merge_methods` is still `["squash"]`, and `allow_auto_merge` is still `true` on the repository — the whole design rests on these three
- [ ] 1.2 Read the ruleset's `bypass_actors` with an admin token and record whether the repository-admin role still bypasses; this is what explains maintainer-authored PRs merging with zero reviews, and `p10` claimed the bypass list was emptied
- [ ] 1.3 Confirm the `verified-commit` App's installation permissions include `pull requests: write` (it opens PRs, so it should) — `enablePullRequestAutoMerge` needs it

## 2. Wire auto-merge into the version-bump PR

- [ ] 2.1 Add `id: create_pr` to the existing `create-pull-request` step in `compose-and-open-pr`; change nothing else about that step
- [ ] 2.2 Add an "Enable auto-merge on the pull request" step after it, using `actions/github-script` with `github-token: ${{ steps.app-token.outputs.token }}` — not `GITHUB_TOKEN`, whose pushes would not trigger `prepare-release.yml`
- [ ] 2.3 Fetch the PR's `node_id` via `pulls.get`, then call `enablePullRequestAutoMerge` with `mergeMethod: SQUASH`
- [ ] 2.4 Gate the step on `steps.create_pr.outputs.pull-request-number != ''` so it covers both the `created` and `updated` cases and no-ops when nothing was opened
- [ ] 2.5 Wrap the mutation in `try`/`catch` reporting through `core.warning`, so a failed enable never fails the job or loses the bump PR
- [ ] 2.6 Comment the step with *why* enabling at open time is not merge-on-green: the ruleset's code-owner review is the gate
- [ ] 2.7 Leave the job's `permissions:` read-only — the App token carries the write scope
- [ ] 2.8 Run `gx lint` and confirm no new finding (no PR-head checkout, no missing permissions, action already pinned in `gx.toml`)

## 3. Record the guardrails the workflow cannot express

- [ ] 3.1 Update `openspec/specs/ci-repo-governance/spec.md` per the delta: the auto-merge requirement now names the ruleset requirements — including code-owner approval — as the merge gate, instead of asserting no approval is required
- [ ] 3.2 State `require_code_owner_review: true` as load-bearing: without it, open-time auto-merge degrades into merging unreviewed version bumps on green
- [ ] 3.3 State that the merge identity must be one whose pushes trigger workflows, and tie it to the visible consequence — no tag, no release, no published image for the new Flutter version

## 4. Verify on the next real bump

- [ ] 4.1 Confirm the workflow log shows auto-merge enabled, and that the PR stays open on green until reviewed
- [ ] 4.2 Approve and confirm the merge lands within seconds, squashed, merged by `verified-commit[bot]`
- [ ] 4.3 Confirm `prepare-release.yml` fires on the resulting push to `main` and creates the tag, and that `release.yml` follows
- [ ] 4.4 Confirm the docs-regeneration push from `update-docs.yml` still lands before any approval, so it never dismisses one
- [ ] 4.5 If the branch went stale behind a Renovate merge, record it — repeated occurrences justify a follow-up (`update_pull_request_branch` on a schedule, or a merge queue)

## 5. Wrap up

- [ ] 5.1 Open as a draft PR quoting the #547 and #541/#542 timings as the evidence for the diagnosis
- [ ] 5.2 Note in the PR description that this corrects a factual claim in the archived `p10-strengthen-branch-protection` proposal (approvals *are* required for bot-authored PRs)
- [ ] 5.3 Record the deferred decision — whether maintainer-authored PRs should get auto-merge too — as a follow-up, gated on the answer to task 1.2
