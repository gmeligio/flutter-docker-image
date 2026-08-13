## Context

Three configuration facts and one timing observation decide everything below. All were read from the live repository on 2026-08-13, not assumed.

**The `main` ruleset (`GET /repos/gmeligio/flutter-docker-image/rules/branches/main`).**

| Rule | Value | Consequence for auto-merge |
| --- | --- | --- |
| `pull_request.required_approving_review_count` | `0` | No numeric approval floor |
| `pull_request.require_code_owner_review` | `true` | With `CODEOWNERS` = `* @gmeligio`, every PR touches owned files |
| `pull_request.dismiss_stale_reviews_on_push` | `true` | A push after approval un-approves the PR |
| `pull_request.require_last_push_approval` | `false` | The approver may be the last pusher |
| `pull_request.allowed_merge_methods` | `["squash"]` | Auto-merge must request `SQUASH` |
| `required_status_checks.strict_required_status_checks_policy` | `true` | The branch must be up to date with `main` to merge |
| `required_status_checks` (6) | `Validate version files`, `Validate generated config`, `Build docs`, `Test Gradle`, `Test image (flutter-android)`, `Test image (flutter-web)` | Auto-merge cannot land on a red or missing check |
| `required_linear_history`, `required_signatures`, `non_fast_forward`, `creation`, `deletion` | enabled | Squash merges through GitHub satisfy all of these |

**Repository settings (`GET /repos/gmeligio/flutter-docker-image`).** `allow_auto_merge: true`, `allow_squash_merge: true`, `allow_merge_commit: false`, `allow_rebase_merge: false`, `delete_branch_on_merge: true`. The feature is already switched on at the repository level — Renovate depends on it.

**The timing observation.** Approval-to-merge intervals on the three most recent automation PRs:

| PR | Author | Checks green | Approved | Merged | By |
| --- | --- | --- | --- | --- | --- |
| #542 | `renovate[bot]` | long before | `07:12:09` | `07:12:11` | `renovate[bot]` |
| #541 | `renovate[bot]` | long before | `09:13:37` | `09:13:39` | `renovate[bot]` |
| #547 | `verified-commit[bot]` | `02:34` | `07:22:19` | `07:23:05` | `gmeligio` (manual) |

Two seconds is a webhook round-trip. Renovate's PRs were merged by GitHub acting on the auto-merge Renovate had enabled, the moment the approval satisfied the last requirement. #547 had no auto-merge enabled, so the same approval did nothing and the merge was a click.

The maintainer's own PRs (#531, #538, #540, #543) merged with zero reviews, so the code-owner requirement does not hold *him* — either because a ruleset bypass still covers the repository-admin role, or because GitHub cannot require an author to approve their own PR. Which one is true does not change this design (it only decides whether a future "auto-merge my own PRs too" change is safe), but it is worth knowing, so confirming it is a task.

## Goals / Non-Goals

**Goals**

- Approving a version-bump PR is sufficient to merge it. No second action.
- No merge requirement is weakened, bypassed, or worked around; the merge is GitHub's, on GitHub's terms.
- The merge continues to trigger `prepare-release.yml`, so tag and release still follow the bump.
- The dependency on the code-owner requirement is written down where a reviewer will see it, because the workflow file cannot express it.

**Non-Goals**

- Auto-merging PRs authored by the maintainer.
- Any form of automated approval.
- Keeping a stale PR branch up to date (a real gap; see Risks).
- Adopting a merge queue or a third-party merge bot.

## Decisions

### Enable auto-merge when the PR is opened, not when it is approved

The obvious reading of "merge after it is approved" is a workflow on `pull_request_review` that reacts to an approval. That mechanism is unnecessary here, because the approval gate lives in the ruleset rather than in the workflow: a PR authored by the `verified-commit` App cannot merge until the code owner approves, whether or not auto-merge is enabled. Enabling auto-merge at open time therefore produces exactly the observed Renovate behaviour — the PR waits, the approval lands, GitHub merges within seconds.

What the open-time approach avoids is a second workflow triggered by `pull_request_review`. That trigger runs in the base-repository context with access to secrets and a write-scoped token — the same trust class as `pull_request_target` — which `p10` deliberately kept out of this repository. It would also need its own author allow-list, its own reviewer-permission check, and a `gx` exemption story (the `pr-head-checkout` rule exists precisely because that class of workflow is easy to get wrong). All of that to reproduce timing GitHub already gives for free.

**Alternatives rejected**

- *`pull_request_review` workflow enabling auto-merge on approval.* More general — it would cover the maintainer's own PRs and any future bot. Rejected as redundant today, and recorded as the migration path if the code-owner requirement is ever relaxed: with `require_code_owner_review: false`, open-time enabling silently degrades into merge-on-green, and the review-triggered form is then the only way to keep approval as the gate.
- *Setting `required_approving_review_count: 1`.* Would make the gate explicit and numeric, but blocks the solo maintainer's own PRs (GitHub forbids self-approval). Rejected in `p10` for the same reason.
- *A merge queue.* Solves the stale-branch problem in Risks properly, by testing each PR against the tip of `main` before merging. Rejected: for a repository merging a handful of PRs a week it adds a full build cycle of latency per merge, and the collision it defends against is rare.
- *Mergify / Kodiak.* A third-party App with write access to a public repository, to obtain a feature GitHub ships natively. Rejected on supply-chain grounds — `p13-scout-sbom-provenance` set the tone here.
- *Auto-approving the bot's PR so it merges on green.* Deletes the only human gate on an unattended weekly commit to `main`. Rejected.

### One step in `compose-and-open-pr`, after the existing PR step

The step belongs in the job that already holds the App token and the PR number. Sketch:

```yaml
- name: Create pull request if there are changes
  uses: peter-evans/create-pull-request@<pinned>
  id: create_pr                       # <- added; the step is otherwise unchanged
  with: ...

# Approval is the last unmet merge requirement for an App-authored PR (the main
# ruleset requires code-owner review), so enabling auto-merge here is what turns
# the maintainer's approval into the merge. It does not merge on green alone.
- name: Enable auto-merge on the pull request
  if: steps.create_pr.outputs.pull-request-number != ''
  uses: actions/github-script@<pinned>
  with:
    github-token: ${{ steps.app-token.outputs.token }}
    script: |
      const number = Number('${{ steps.create_pr.outputs.pull-request-number }}')
      const { data: pr } = await github.rest.pulls.get({ ...context.repo, pull_number: number })
      try {
        await github.graphql(
          `mutation($id: ID!) {
             enablePullRequestAutoMerge(input: { pullRequestId: $id, mergeMethod: SQUASH }) {
               clientMutationId
             }
           }`,
          { id: pr.node_id },
        )
        core.info(`Auto-merge enabled on #${number}; it will merge once the code owner approves.`)
      } catch (error) {
        core.warning(`Could not enable auto-merge on #${number}: ${error.message}`)
      }
```

Four things in that sketch are load-bearing:

1. **`mergeMethod: SQUASH`.** The ruleset's `allowed_merge_methods` is `["squash"]` and the repository disables merge commits and rebase merges. Any other value fails the mutation. Squashing through GitHub also produces the signed, linear commit that `required_signatures` and `required_linear_history` demand.
2. **The App token, not `GITHUB_TOKEN`.** GitHub attributes the eventual merge to whoever enabled auto-merge. Pushes made with `GITHUB_TOKEN` do not trigger workflow runs, and this merge *must* trigger `prepare-release.yml` — otherwise the tag is never created, `release.yml` never runs, and the new image is never published. The `verified-commit` App is already used in this workflow for exactly this reason (its step is named "Generate authentication token with GitHub App to trigger Actions") and already holds `pull requests: write`, since it opens the PR. The job's own `permissions:` stays read-only, as `ci-workflow-hardening` requires.
3. **`enablePullRequestAutoMerge` is GraphQL-only**, and it needs the PR's `node_id`, which `create-pull-request` does not output — hence the `pulls.get`. (`gh pr merge --auto --squash <n>` with `GH_TOKEN` set to the App token is a one-line equivalent; `github-script` is preferred because the failure handling below is explicit rather than a shell `|| true`, and the action is already pinned in `gx.toml`.)
4. **The `try`/`catch`.** Enabling auto-merge is an optimisation on top of a PR that is already correct. If the mutation fails, the desired outcome is "maintainer merges by hand this week", which is today's behaviour — not a red workflow run and an unexplained missing bump.

The step is gated on `pull-request-number` being non-empty rather than on `pull-request-operation == 'created'`. When the workflow re-runs and *updates* an existing bump PR, that push dismisses the stale approval and re-enabling auto-merge is a harmless no-op if it is already on; skipping the `updated` case would leave a re-pushed PR without it.

### The known-benign failure: "clean status"

`enablePullRequestAutoMerge` errors with `Pull request is in clean status` when every merge requirement is *already* satisfied — GitHub's position being that there is nothing to wait for, so the caller should merge instead. Under today's ruleset this cannot happen at open time (checks have not run, and the code owner has not approved), but it is exactly what would be seen if the code-owner requirement were removed. Treating it as a warning rather than falling back to a direct merge is deliberate: if this repository ever reaches a state where the bump PR is immediately mergeable, the correct outcome is a human noticing, not automation merging an unreviewed version bump within seconds of opening it.

## Risks

- **A stale branch stalls the merge, silently.** `strict_required_status_checks_policy: true` requires the PR branch to be current with `main`. GitHub's auto-merge does not rebase or update the branch. `update-version.yml` and Renovate both run in the same early-morning window (#547 opened `02:04`; #541/#542 opened `02:16`), so a Renovate PR merging first leaves the bump PR out of date and auto-merge waiting with no notification. Mitigation today: the maintainer clicks "Update branch", which re-runs the checks and — because `dismiss_stale_reviews_on_push: true` — dismisses the approval, so it must be re-approved. Worth watching; if it happens more than occasionally, the fix is either a scheduled `update_pull_request_branch` call or a merge queue.
- **Any post-approval push un-approves the PR.** Same rule, other direction. `update-docs.yml`'s `generate` job pushes regenerated docs onto the PR branch, and `config/version.json` is a docs generator source — so a bump PR *does* receive an automated push. On #547 it landed at `02:04:44`, five hours before the approval, which is the normal ordering. If it ever lands after an approval, the PR quietly stops being mergeable.
- **The gate is invisible in the diff.** The workflow step says "enable auto-merge"; nothing in the file says "and a human must approve first". That fact lives in an externally-managed ruleset. The spec delta is the mitigation: `require_code_owner_review: true` becomes a stated, load-bearing guardrail rather than an incidental setting.
- **Merge attribution changes.** `main`'s history will show the version-bump squash authored by the App rather than the maintainer. Cosmetic, but it is the signal that the merge was automated, and `release.yml`'s notes are generated from history.

## Verification plan

Every claim below is checkable on the next real version bump; none of it can be exercised locally.

1. On the run that opens the next bump PR, confirm the step logged "Auto-merge enabled" and the PR shows the auto-merge banner while staying unmerged on green.
2. Approve it and confirm the merge lands within seconds, as a squash, with `verified-commit[bot]` as the merging actor.
3. Confirm `prepare-release.yml` runs on the resulting push to `main` and creates the tag — this is the one property that would break the release chain if the merge identity behaved like `GITHUB_TOKEN`.
4. Read the ruleset's `bypass_actors` with an admin token to settle why maintainer-authored PRs merge unreviewed, and record the answer in the archived change.
