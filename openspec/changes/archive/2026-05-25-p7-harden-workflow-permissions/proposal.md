## Why

Scorecard's live findings (https://github.com/gmeligio/flutter-docker-image/security/code-scanning) report **8 high-severity `TokenPermissionsID` alerts** plus several workflows with no top-level `permissions:` block at all. Two are concrete gaps in this repo's workflow YAML, not transitive package CVEs:

- `.github/workflows/changelog.yml:1` and `.github/workflows/tag.yml:1` have **no `permissions:` block**, so jobs inherit the repo-default `GITHUB_TOKEN` scope. Both push commits/tags via a GitHub App token, so the implicit broad scope is unused but visible to a compromised step.
- Several push-triggered release-path workflows (`changelog.yml`, `tag.yml`, `release.yml`, `update_version.yml`, `update_docs.yml`, `ci.yml`, `scorecard.yml`) have **no `concurrency:` block**. Two pushes to `main` in quick succession can race on tags or commits.
- Two third-party actions are pinned to different versions across workflows: `docker/metadata-action` at v5.10.0 (`build.yml:105`, `ci.yml:50`, `release.yml:41,118`) vs v5.7.0 (`windows.yml:48`), and `docker/scout-action` at v1.20.4 (`build.yml:259`) vs v1.18.2 (`release.yml:228`). Drift makes Dependabot bumps noisier and means one workflow runs unreviewed older code.
- No workflow uses `step-security/harden-runner`. Recent 2026 supply-chain incidents (hackerbot-claw, TanStack npm compromise) abused unmonitored runner network egress that harden-runner would have logged.
- The repo does **not** currently use `pull_request_target` (verified by grep). This is the safe state. The community-documented "pwn request" pattern (JFrog, Wiz, StepSecurity) makes adding it a per-workflow risk decision, not a default — there should be a written policy preventing accidental introduction.

This change closes the actionable workflow-content findings from Scorecard and codifies the safe `pull_request` posture, without touching workflow structure (left for p8/p9) or base-image CVEs (separate track).

## What Changes

- **Add top-level `permissions:` blocks** to `changelog.yml` and `tag.yml` with the minimum needed — `contents: read` at workflow level, escalated to `contents: write` only on the job that pushes (both already use App tokens for the actual push, so the `GITHUB_TOKEN` scope can stay read-only; the missing block is the finding).
- **Add `concurrency:` blocks** to push-triggered workflows that mutate shared state: `changelog.yml`, `tag.yml`, `release.yml`, `update-version.yml`, `update-docs.yml`, `ci.yml`. Group by `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: false` for release-path workflows (cleanup-style, must not race) and `cancel-in-progress: true` for `ci.yml` (latest commit wins).
- **Sync action versions across workflows**: pin `docker/metadata-action` and `docker/scout-action` to a single SHA each, repo-wide. Update `windows.yml:48` and `release.yml:228` to match the newer pin already in use elsewhere.
- **Add `step-security/harden-runner` in `audit` mode** at the first step of every job. Audit mode logs egress without blocking; once a baseline is established (~2 weeks), the proposal author may flip individual jobs to `block` in a follow-up. No traffic is blocked in this change.
- **Add a written workflow-security policy** at `.github/workflows/SECURITY.md` covering: no `pull_request_target` without security review, no `actions/checkout` of `${{ github.event.pull_request.head.sha }}` in privileged workflows, SHA-pinning required, App tokens preferred over PATs. This is the durable rule, not a memo.
- No renames in this change — leaving the workflow file names alone keeps the diff focused on permissions. (Rename to kebab-case happens in p9.)

## Capabilities

### New Capabilities

- `ci-workflow-hardening`: defines the security posture that every workflow under `.github/workflows/` SHALL satisfy — minimum-scope permissions, concurrency on push-triggered shared-state mutations, SHA-pinned and version-consistent third-party actions, runner egress observability, and the `pull_request`-only PR-trigger policy.

### Modified Capabilities

_None._

## Impact

- **Affected files**: every workflow under `.github/workflows/` (one-line `permissions:` and `concurrency:` additions on most; harden-runner step prepended to each job); two SHA updates in `windows.yml` and `release.yml`; new `.github/workflows/SECURITY.md`.
- **Behavioral change**: none visible to image users. CI runs gain a harden-runner step (~2 s overhead per job) and the `concurrency:` queue may delay a second push briefly.
- **Risk**: harden-runner audit mode is non-blocking, so it cannot break a job. The concurrency change can serialize back-to-back pushes — for `ci.yml` we accept cancellation; for release-path workflows we accept short queueing (the alternative is the existing race).
- **Risk**: Scorecard may take one run cycle to re-grade. Verified by waiting for the next scheduled scan after merge.
- **Depends on**: none.
- **Out of scope**: extraction of repeated steps into composite actions (p8), reusable workflows / file renames (p9), base-image CVE remediation, `BranchProtectionID` and `CodeReviewID` Scorecard findings (repo settings, separate track).
