## 1. Add missing permissions blocks

- [x] 1.1 Add top-level `permissions: { contents: read }` to `.github/workflows/changelog.yml` (currently missing — Scorecard `TokenPermissionsID` will detect this on the next scan).
- [x] 1.2 Add top-level `permissions: { contents: read }` to `.github/workflows/tag.yml` (currently missing).
- [x] 1.3 Audit every other workflow's top-level `permissions:` and tighten any that are broader than needed. Cross-check against the 8 open `TokenPermissionsID` alerts in code-scanning. _Audit result: every other workflow already declares `permissions: contents: read` at workflow level with job-level escalation comments. The 8 `TokenPermissionsID` Scorecard alerts are flagging required job-level writes (`packages: write` in `cleanup_pr_image.yml`, `release.yml`; `contents: write` in `update_version.yml`; `security-events: write` in `build.yml`, `release.yml`, `scorecard.yml`; etc.) — those scopes are functionally required to push images/commits/SARIF. The workflow-level scope is already minimal._

## 2. Add concurrency blocks to push-triggered shared-state workflows

- [x] 2.1 `ci.yml`: add `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`.
- [x] 2.2 `changelog.yml`, `tag.yml`, `release.yml`, `update_version.yml`, `update_docs.yml`: add the same group expression with `cancel-in-progress: false` — release-path workflows must serialize, not cancel.
- [x] 2.3 `scorecard.yml`: add concurrency with `cancel-in-progress: true` (scheduled scan; superseding run is fine).

## 3. Sync drifted action versions

- [x] 3.1 Update `.github/workflows/windows.yml:48` `docker/metadata-action` from v5.7.0 (SHA `902fa8ec…`) to v5.10.0 (SHA `c299e40c…`) to match the rest of the repo.
- [x] 3.2 Update `.github/workflows/release.yml:228` `docker/scout-action` from v1.18.2 (SHA `f8c77682…`) to v1.20.4 (SHA `bacf462e…`) to match `build.yml:259`.
- [x] 3.3 Grep for any other action whose SHA pin differs across files; record findings and align on the newer pin. _Found one additional drift: `actions/download-artifact` was pinned to v4 (SHA `d3f86a10…`) in `build.yml:183,220` vs v6.0.0 (SHA `018cc2cf…`) elsewhere. Aligned to v6.0.0. Also removed three stale `[actions.overrides]` entries in `.github/gx.toml` that pinned the now-bumped versions; `gx tidy` confirms `Up to date`, `gx lint` passes with no issues._

## 4. Add harden-runner in audit mode

- [x] 4.1 Add `step-security/harden-runner@<SHA-of-v2-latest> with egress-policy: audit` as the first step of every job in every workflow. _Pinned to v2.19.4 (SHA `9af89fc7…`). Added to 26 Linux jobs across all 11 workflows. Skipped 2 Windows jobs (`release.yml/release_windows`, `windows.yml/test_windows`) — `step-security/harden-runner` does not support `windows-2025` runners. Added `step-security/harden-runner = "^2"` to `[actions]` in `.github/gx.toml`._
- [x] 4.2 Note: do NOT use `egress-policy: block` in this change — establishing the egress baseline is a follow-up. _Confirmed: every insertion uses `egress-policy: audit`._

## 5. Write the workflow-security policy

- [x] 5.1 Document the six rules: `pull_request_target` ban, SHA pinning, App tokens over PATs, `harden-runner` first step, minimum-scope `permissions:`, `concurrency:` on push-triggered shared-state workflows. _Authored as a "Workflow security rules" subsection inside `docs/src/contributing.mdx` rather than a standalone `.github/workflows/SECURITY.md`. Rationale: rules are operational guidance for contributors who already read `contributing.mdx` before editing workflows; co-locating with the existing "Editing GitHub Actions workflows" section maximizes follow-rate and avoids a second outlier file in `.github/workflows/`. The `ci-workflow-hardening` spec remains the authoritative source — `contributing.mdx` points to it._
- [x] 5.2 Link the policy from the existing contributor docs. _The rules ARE the contributor doc now — folded into `docs/src/contributing.mdx`. Regenerated `docs/contributing.md` via `pnpm run build`._

## 6. Verify (post-merge — not actionable before PR lands)

- [ ] 6.1 After merge, wait for the next scheduled `scorecard.yml` run; confirm the 2 `TokenPermissionsID` alerts on `changelog.yml` and `tag.yml` (and any others addressed) move to closed.
- [ ] 6.2 Trigger two `workflow_dispatch` runs of `release.yml` back-to-back; confirm the second queues rather than races (`cancel-in-progress: false` behavior).
- [ ] 6.3 Inspect a harden-runner job summary and confirm the egress baseline is recorded; file a follow-up issue listing every observed domain (input to a future `block` policy).
