## Why

Two workflows push commits **directly to `main`**, bypassing the branch ruleset:

- `prepare-release.yml` — commits `changelog.md` via `grafana/github-api-commit-action` (`prepare-release.yml:71-76`), then creates the version tag.
- `update-docs.yml` — commits regenerated docs the same way (`update-docs.yml:50-56`).

Both authenticate as the `verified-commit` GitHub App, and the only reason they work is the ruleset's bypass actor (`actor_id: 987256, bypass_mode: always`). That bypass is the single loophole in an otherwise strong ruleset (linear history, signed commits, no force-push, required status checks, CODEOWNERS review). Every direct push to `main` is an unreviewed write to the protected branch — the exact thing the ruleset exists to prevent.

`changelog.md` is **documentation only** — nothing reads the committed file. `release.yml` regenerates its own changelog from git history at release time (`release.yml:301`, `git-cliff --latest --no-exec` into a temp file) for the GitHub Release body; `ci.yml` actively ignores `changelog.md` (`paths-ignore`). Because the committed changelog gates nothing, it does not need to land before the tag — it can be generated in the **same PR that bumps the version**, which is what the `# TODO` at `update-version.yml:518` already anticipates. This lets `prepare-release.yml` shed its changelog-commit step entirely and collapse to a single tag-creation job.

Separately, Renovate's PRs (Mend hosted app) require a manual merge click today even though they only ever touch lockfiles/config and pass all required checks. Because `required_approving_review_count` is `0`, these PRs are already mergeable the moment checks go green — they just aren't merged automatically.

### What this change does, and what it deliberately does not

This change routes **all writes to `main` through pull requests** and lets GitHub auto-merge the safe automated ones. As a consequence, the ruleset's bypass actor is no longer needed and is removed. The end state: there is no path to `main` that skips the ruleset.

The ruleset itself is **managed as code outside this repository**. This change does NOT version the ruleset in-repo, does NOT add a governance/SECURITY document, and does NOT add an auto-approve workflow or any `pull_request_target` trigger. Those were earlier ideas for this change; research showed the ruleset-as-code belongs with the external tooling, and that — because approvals gate nothing at `required_approving_review_count: 0` — auto-approval is unnecessary. Native GitHub auto-merge plus the existing required checks achieve the goal with no new workflow and no new attack surface.

### Scorecard honesty

Removing the bypass actor sets Scorecard's `EnforceAdmins` to `true`, but that is a Tier-5 signal only scored with an admin token and unreachable while `required_approving_review_count` stays `0` (a deliberate solo-maintainer choice — GitHub forbids self-approval). So the measurable Scorecard movement is ~0. This change is made for correct posture (no unreviewed writes to `main`), not for score.

## What Changes

- **`update-version.yml`** — add a `git-cliff --tag <new-version>` step that regenerates `changelog.md` for the new version, before the existing `create-pull-request` step. The changelog rides along in the same version-bump PR (`create-pull-request` already stages all changes). `git-cliff --tag` takes the version as an argument and does not require the tag to exist, so there is no chicken-and-egg with tag creation.
- **`prepare-release.yml`** — remove the changelog-commit job entirely. The workflow collapses to a single `create-tag` job triggered by a push to `main` touching `config/version.json`: read the version, create the tag, done. No direct push, no PR, no changelog generation here.
- **`update-docs.yml`** — replace the direct docs push with `peter-evans/create-pull-request` (already a pinned dependency, used in `update-version.yml:520`) + auto-merge.
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

- **Affected files**: `.github/workflows/update-version.yml`, `.github/workflows/prepare-release.yml`, `.github/workflows/update-docs.yml`, `.github/renovate.json`.
- **External (cross-repo)**: the ruleset bypass actor is removed in the external ruleset code in the same rollout.
- **Behavioral change**: the changelog is now generated inside the version-bump PR (reviewed alongside the version change) instead of as a separate post-merge direct push. `prepare-release.yml` no longer pushes anything — it only tags. Docs regeneration lands via an auto-merged PR. Renovate PRs merge automatically instead of needing a manual click.
- **Source of truth**: `config/version.json` unambiguously gates a release — a new `flutter.version` lands (with its changelog) via the version-bump PR, and merging it triggers the tag, which triggers `release.yml`. `changelog.md` is documentation that rides along; it gates nothing.
- **Risk**: `platformAutomerge` could merge a failing PR if no required check exists — not applicable here (5 required checks present), but the renovate change must not remove that precondition.
- **Depends on**: `p7-harden-workflow-permissions` (archived) for workflow-hardening conventions.
