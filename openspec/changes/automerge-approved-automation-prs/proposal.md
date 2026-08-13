## Why

The weekly version-bump PR is merged by hand, and the click is the only manual step left in the release chain.

PR [#547](https://github.com/gmeligio/flutter-docker-image/pull/547) is the reference case. `update-version.yml` opened it at `02:04`, every required check was green by `02:34`, the maintainer approved at `07:22:19` — and then merged it manually at `07:23:05`. Those 46 seconds are the whole defect: the approval had already expressed the decision, and nothing acted on it.

Contrast the Renovate PRs from three days earlier. [#542](https://github.com/gmeligio/flutter-docker-image/pull/542) was approved at `07:12:09` and merged by `renovate[bot]` at `07:12:11`; [#541](https://github.com/gmeligio/flutter-docker-image/pull/541) approved at `09:13:37`, merged at `09:13:39`. Two seconds each, hours after their checks went green. That is GitHub-native auto-merge firing on the approval event: Renovate enables auto-merge when it opens the branch (`"automerge": true` with `platformAutomerge` at its default), so approval is the last unmet merge requirement and GitHub merges the instant it arrives.

**The behaviour this change asks for already exists in this repository.** It is simply never enabled on the PRs `update-version.yml` opens. `peter-evans/create-pull-request` opens the PR and the job ends; no step calls `enablePullRequestAutoMerge`.

### Why approval is the gate, and why that is not an accident

The `main` ruleset sets `required_approving_review_count: 0` but also `require_code_owner_review: true`, with `CODEOWNERS` reading `* @gmeligio`. Empirically the code-owner requirement is what holds automation PRs: #541 and #542 sat green and unmerged for hours until the review landed, then merged within two seconds. So for a PR authored by `renovate[bot]` or `verified-commit[bot]`, "all requirements met" includes "the code owner approved".

This matters because it means enabling auto-merge at PR-open time is *not* the same as merging on green. The archived `p10-strengthen-branch-protection` proposal recorded the opposite belief — "approvals are not required to merge (`required_approving_review_count` is `0`)" — and the merge timings above show that is wrong for bot-authored PRs. The `ci-repo-governance` spec inherited the error and is corrected here.

## What Changes

- **`.github/workflows/update-version.yml`** — after the `create-pull-request` step in `compose-and-open-pr`, add one step that enables GitHub-native auto-merge (`SQUASH`, the only method the ruleset allows) on the PR it just opened or updated, authenticated with the existing `verified-commit` App token. Enabling is best-effort: a failed mutation logs and does not fail the job, because a version-bump PR that exists but lacks auto-merge is a working outcome, while a red job is not.
- **`openspec/specs/ci-repo-governance/spec.md`** — correct the auto-merge requirement to state the real gate (ruleset requirements including code-owner approval, not "no approval step"), extend it to cover PRs opened by `update-version.yml`, and record two guardrails the behaviour now leans on: `require_code_owner_review` staying `true`, and the merge being performed by an identity whose pushes trigger workflows.

Nothing else changes. No new workflow, no new trigger, no new App, no ruleset edit, no change to Renovate's configuration.

### Deliberately not in scope

- **A `pull_request_review`-triggered workflow** that enables auto-merge on any approved PR. It is the more general mechanism and it is not needed: the approval gate already comes from the ruleset, so enabling at open time produces identical timing with no new workflow and no new write-scoped trigger. Kept as the documented fallback in `design.md` if the code-owner requirement is ever relaxed.
- **The maintainer's own PRs.** They merge today with zero reviews (#531, #538, #540, #543), so auto-merge on them would mean merge-on-green with no human gate at all. Different decision, different risk, not bundled here.
- **Auto-approval of automation PRs.** It would delete the only human gate on an unattended weekly commit to `main`. Explicitly rejected, as it was in `p10`.
- **Automatically updating a stale PR branch.** `strict_required_status_checks_policy: true` means an out-of-date branch stalls auto-merge; the mitigation today is the maintainer's "Update branch" click. See `design.md` "Risks" — this is the one failure mode that leaves a PR silently waiting.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `ci-repo-governance`: the auto-merge requirement is corrected and widened — every trusted-automation PR (Renovate *and* the version-bump PR) has auto-merge enabled at creation, and the merge fires on the ruleset's terms, with code-owner approval as the human gate.

## Impact

- **Affected files**: `.github/workflows/update-version.yml` (one step, plus an `id:` on the existing PR step), `openspec/specs/ci-repo-governance/spec.md`.
- **Behavioural change**: approving a version-bump PR merges it. The maintainer's action changes from *approve, then merge* to *approve*.
- **Release chain**: the merge commit is authored by the `verified-commit` App instead of the maintainer. The push to `main` must still trigger `prepare-release.yml` (tag) → `release.yml` (publish). This is why the App token is used rather than `GITHUB_TOKEN`, whose pushes do not trigger workflows — and it is the single property to confirm on the first real run.
- **Risk**: none of the merge requirements weaken. Auto-merge cannot merge a PR that a human has not approved, cannot merge on a red or missing check, and is disabled by GitHub if the PR becomes conflicted. The exposure is a configuration one — if `require_code_owner_review` is ever set to `false`, version bumps would begin merging unreviewed on green. That coupling is invisible in the workflow file, which is why it is written into the spec.
- **Depends on**: `p10-strengthen-branch-protection` (archived) — this change corrects one factual claim in that proposal's spec and completes the coverage it intended.
