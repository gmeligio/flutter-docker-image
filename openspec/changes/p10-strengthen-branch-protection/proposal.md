## Why

Two Scorecard alerts in `https://github.com/gmeligio/flutter-docker-image/security/code-scanning` are repo-governance, not workflow-content:

- **`BranchProtectionID`, severity high, score 4/10** — *"branch 'main' does not require approvers; 'last push approval' is disabled; 'branch protection settings apply to administrators' is disabled"*.
- **`CodeReviewID`, severity high, score 0/10** — *"Found 1/29 approved changesets — score normalized to 0"*.

### The solo-maintainer reality

This repo has one maintainer (`gmeligio`). Over the last 30 closed PRs, the author distribution is `gmeligio: 27, verified-commit[bot]: 2, therickys93: 1`. GitHub does not allow self-approval, so **raising `required_approving_review_count` above 0 would block every maintainer PR**, the dominant ~90 % of the changeset stream. The Scorecard `CodeReviewID` finding is **structurally unsolvable without a co-maintainer** — it is an accepted ceiling, not a fixable bug. Honesty here matters: a proposal that pretends otherwise burns maintainer velocity for cosmetic score points.

What IS actionable for a solo maintainer:
1. **Capture the ruleset as code.** The current ruleset (`gh api repos/.../rulesets/1959230`) is already strong (linear history, signed commits, no force-push, no deletion, required status checks, CODEOWNERS review). Versioning it in `.github/rulesets/main.json` gives drift visibility and lets a future ruleset edit go through PR review like any other code change.
2. **Audit the bypass actor.** The active ruleset has `bypass_actors: [{actor_id: 987256, actor_type: Integration, bypass_mode: always}]`. Identify which App this is, confirm it is still needed (likely `verified-commit` so `changelog.yml` / `tag.yml` can push), and either narrow the bypass mode to `pull_request` or remove the entry if unused. This is the warning Scorecard surfaces as *"branch protection settings apply to administrators is disabled"* — any non-`never` bypass weakens the rule.
3. **Auto-approve Renovate's PRs.** Renovate (`.github/renovate.json`) groups non-major bumps on a weekly schedule and major action bumps monthly. Adding an auto-approve workflow lifts those changesets out of the unapproved bucket, modestly raising `CodeReviewID` over the rolling 30-PR window. Leverage is low (~5–10 % of PRs at current volume) but cost is also low and the workflow is reusable if a co-maintainer arrives later.
4. **Explicitly accept the residual Scorecard score.** Document that `CodeReviewID < 10` is an accepted solo-maintainer constraint, with the recovery path being "add a co-maintainer". A SECURITY.md or governance note records this so future readers and auditors don't re-open it as a finding.

### Out of scope, by intent

- **Requiring approving reviews on human PRs.** This would block the maintainer's own work; rejected as cost > benefit for a solo repo.
- **Requiring last-push approval.** Meaningful only when reviews are required; would not improve the active gate.
- **Base-image transitive CVEs** (`CVE-2020-8908`, `CVE-2021-22569`, … etc., reported by Docker Scout against Android SDK / Ruby stdlib / Python setuptools transitive dependencies). These ship inside vendor-provided SDKs and are outside the maintainer's control until upstream Flutter / Android tooling updates. Acknowledged and accepted.

## What Changes

- **Add `.github/rulesets/main.json`** — the `PUT /repos/{owner}/{repo}/rulesets/1959230` request shape, derived from a live `gh api` dump. Strip API-only fields (`id`, `node_id`, `created_at`, `updated_at`, `source`, `source_type`, `_links`, `current_user_can_bypass`). Include a sibling `.github/rulesets/README.md` documenting the apply command and the rule that ruleset edits go through PR review.
- **Audit `bypass_actors`** — resolve `actor_id: 987256` (run `gh api /repos/gmeligio/flutter-docker-image/installation` and cross-reference). If it is the `verified-commit` App used by `changelog.yml` / `tag.yml`, keep the entry but consider narrowing `bypass_mode` from `always` to `pull_request` so the App can only bypass via merging a PR, not via direct push. If it is something else, remove it.
- **Add `.github/workflows/auto-approve-bots.yml`** — triggered on `pull_request_target: { types: [opened, synchronize, reopened] }`. NO `actions/checkout` of PR contents. Body: if `github.event.pull_request.user.login` is in a hard-coded allowlist (`renovate[bot]`, `verified-commit[bot]`) AND every changed file matches a hard-coded path allowlist (`renovate.json`, `package*.json`, `pnpm-lock.yaml`, `mise.toml`, `.github/gx.toml`, `changelog.md`, `config/version.json`), call `pulls.createReview({event: 'APPROVE'})` via the existing `VERIFIED_COMMIT_ID` / `VERIFIED_COMMIT_KEY` App token (different actor from the PR author — GitHub accepts the approval). Fails closed if either allowlist misses. Logs each decision to the run summary.
- **Add `.github/SECURITY.md`** (separate from `.github/workflows/SECURITY.md` added in p7) — at the repository level, document the governance model: sole maintainer, ruleset link, why `CodeReviewID` will not reach 10, what would change if a co-maintainer joins.
- **Do NOT modify ruleset `1959230`'s `required_approving_review_count` or `require_last_push_approval`.** Both stay at their current values (`0`, `false`). The ruleset-as-code file captures the deliberate choice, with a comment explaining why.

### Threat model for the `pull_request_target` use in `auto-approve-bots.yml`

p7's `ci-workflow-hardening` spec requires every new `pull_request_target` introduction to document its threat model. For this workflow:

- **Risk NOT introduced**: code execution from a fork. The workflow does NOT `actions/checkout` PR HEAD. Inputs read from `github.event.*` are `user.login` and the changed file paths returned by `pulls.listFiles`; neither is interpolated into a shell command.
- **Risk accepted**: if a future maintainer extends the author allowlist without reviewing the changed-path allowlist, a compromised bot account could ship a malicious change to a config-only path. Mitigations: (a) author allowlist is explicit (no glob), (b) path allowlist is explicit (no glob), (c) any change to either list goes through the ruleset (so the maintainer reviews their own diff in the PR UI, even though they can't formally approve it), (d) the App token is single-repo scoped, (e) every decision is logged to the run summary for audit.
- **Why this trigger**: the alternative is a two-workflow `pull_request` + `workflow_run` split, which adds indirection for no benefit here — we don't check out PR contents, so there's no untrusted code to isolate. The minimum-surface choice is `pull_request_target` with strict input handling and no checkout.

## Capabilities

### New Capabilities

- `ci-repo-governance`: the contract for what this repo's branch-protection / ruleset / code-review posture SHALL satisfy, given the solo-maintainer constraint — what's enforced, what's deliberately not enforced, where the rules live, and how Scorecard's residual findings are accepted.

### Modified Capabilities

_None._

## Impact

- **Affected files**: `.github/rulesets/main.json` (new), `.github/rulesets/README.md` (new), `.github/workflows/auto-approve-bots.yml` (new), `.github/SECURITY.md` (new). Ruleset `1959230`'s `bypass_actors` updated out-of-band via `gh api PUT` if the audit finds a tightening opportunity.
- **Behavioral change for the maintainer**: none. PR flow stays identical. Renovate PRs auto-merge faster (status-checks-pass + auto-approval → auto-merge if `automergeType: pr` is set in renovate config; not changed by this proposal).
- **Risk**: the `pull_request_target` workflow is new attack surface even with no checkout — mitigated by the threat model above and the absence of `actions/checkout`. Periodic re-review (annual or when adding to either allowlist) is recommended.
- **Risk**: Scorecard's `CodeReviewID` may not improve much. Renovate at current settings (weekly non-major group, monthly major group) produces ~4–8 PRs/month; the rolling 30-PR window is dominated by maintainer PRs that cannot be approved. The score may move from `0/10` toward `2/10`–`3/10`. The proposal accepts this; the auto-approve workflow is included because it is the right architecture, not because it solves the score.
- **Risk**: tightening `bypass_actors` from `always` to `pull_request` could break `changelog.yml` / `tag.yml` if those workflows push commits directly (without a PR). Verify before applying — if they do push directly, leave the bypass mode alone and document why.
- **Depends on**: `p7-harden-workflow-permissions` archived (its `ci-workflow-hardening` spec defines the `pull_request_target` review process this proposal follows).
- **Out of scope** (explicitly listed for the future reader): co-maintainer onboarding; requiring approving reviews; base-image transitive CVEs (vendor-controlled).
- **In scope, by virtue of being authoritative for branch protection**: the ruleset-as-code file SHALL list `gx lint` (the job exposed by `.github/workflows/gx.yml`) as a required status check. That job already runs on every PR; making it required closes the gap where a PR with failing lint could merge if the check was not blocking. After p8-enforce-workflow-policy-via-gx archives, the same required check also enforces every structural requirement in `ci-workflow-hardening` (per p8's spec delta). If p9 lands later and renames the gx job, this file is updated in the same commit as the rename to keep the required-check name in sync.
