## Why

Two workflows push commits **directly to `main`**, bypassing the branch ruleset:

- `prepare-release.yml` — commits `changelog.md` via `grafana/github-api-commit-action` (`prepare-release.yml:71-76`).
- `update-docs.yml` — commits regenerated docs the same way (`update-docs.yml:50-56`).

Both authenticate as the `verified-commit` GitHub App, and the only reason they work is the ruleset's bypass actor (`actor_id: 987256, bypass_mode: always`). That bypass is the single loophole in an otherwise strong ruleset (linear history, signed commits, no force-push, required status checks, CODEOWNERS review). Every direct push to `main` is an unreviewed write to the protected branch — the exact thing the ruleset exists to prevent.

Separately, Renovate's PRs (Mend hosted app) require a manual merge click today even though they only ever touch lockfiles/config and pass all required checks. Because `required_approving_review_count` is `0`, these PRs are already mergeable the moment checks go green — they just aren't merged automatically.

### What this change does, and what it deliberately does not

This change routes **all writes to `main` through pull requests** and lets GitHub auto-merge the safe automated ones. As a consequence, the ruleset's bypass actor is no longer needed and is removed. The end state: there is no path to `main` that skips the ruleset.

The ruleset itself is **managed as code outside this repository**. This change does NOT version the ruleset in-repo, does NOT add a governance/SECURITY document, and does NOT add an auto-approve workflow or any `pull_request_target` trigger. Those were earlier ideas for this change; research showed the ruleset-as-code belongs with the external tooling, and that — because approvals gate nothing at `required_approving_review_count: 0` — auto-approval is unnecessary. Native GitHub auto-merge plus the existing required checks achieve the goal with no new workflow and no new attack surface.

### Scorecard honesty

Removing the bypass actor sets Scorecard's `EnforceAdmins` to `true`, but that is a Tier-5 signal only scored with an admin token and unreachable while `required_approving_review_count` stays `0` (a deliberate solo-maintainer choice — GitHub forbids self-approval). So the measurable Scorecard movement is ~0. This change is made for correct posture (no unreviewed writes to `main`), not for score.

## What Changes

- **`prepare-release.yml`** — replace the direct changelog push with `peter-evans/create-pull-request` (already a pinned dependency, used in `update-version.yml:520`). The changelog commit lands on a branch and opens a PR with auto-merge enabled. The `create-tag` job must trigger off the **merged** changelog commit, not the in-job `needs:` sequence (see design.md — this is the one real design risk).
- **`update-docs.yml`** — replace the direct docs push with the same `create-pull-request` + auto-merge pattern.
- **`renovate.json`** — add `"automerge": true` and `"platformAutomerge": true` so GitHub auto-merges Renovate PRs once required checks pass. No approval needed (count is `0`); ≥1 required check is present (5 exist), satisfying `platformAutomerge`'s safety precondition.
- **Remove the ruleset bypass actor** — done in the **external** ruleset code, not here. The version tag push (`script/createGitTag.js:21`, `refs/tags/*`) is unaffected: the ruleset targets `~DEFAULT_BRANCH` (branches) only, so tag creation never needed the bypass. Recorded here as a cross-repo follow-up so the in-repo workflow change and the external ruleset change land together.

### Out of scope, by intent

- **In-repo ruleset-as-code** (`.github/rulesets/main.json`) — the ruleset is managed externally; duplicating it here would create a second source of truth and expose `bypass_actors` (a field GitHub hides from public readers) in a public repo.
- **Governance / SECURITY document** — not adding one.
- **Auto-approve workflow / `pull_request_target`** — unnecessary; approvals gate nothing at count `0`.
- **Requiring approving reviews** — would block the solo maintainer's own PRs.

## Capabilities

### New Capabilities

- `ci-repo-governance`: the contract for how writes reach `main` — every write goes through a reviewed-or-auto-merged PR, no bypass actor exists, and trusted automated PRs (Renovate, release/docs bots) auto-merge on green checks.

### Modified Capabilities

_None._

## Impact

- **Affected files**: `.github/workflows/prepare-release.yml`, `.github/workflows/update-docs.yml`, `.github/renovate.json`.
- **External (cross-repo)**: the ruleset bypass actor is removed in the external ruleset code in the same rollout.
- **Behavioral change**: release and docs regeneration now land via auto-merged PRs instead of direct pushes — one extra CI round-trip per release/docs update, and a brief window where the PR is open before auto-merge. Renovate PRs merge automatically instead of needing a manual click.
- **Risk**: the release chain (`changelog PR → merge → tag → release.yml`) must re-trigger correctly once the changelog lands via a *merged* PR rather than a direct push. Detailed in design.md; verified in tasks.
- **Risk**: `platformAutomerge` could merge a failing PR if no required check exists — not applicable here (5 required checks present), but the renovate change must not remove that precondition.
- **Depends on**: `p7-harden-workflow-permissions` (archived) for workflow-hardening conventions.
