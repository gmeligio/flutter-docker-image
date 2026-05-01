## 1. Generate manifest and lock locally

- [x] 1.1 Install `gx` locally (`brew install gmeligio/tap/gx` or `cargo install gx`) and verify with `gx --version`
- [x] 1.2 Run `gx init` at the repo root; confirm it generates `.github/gx.toml` and `.github/gx.lock` from existing SHA-pinned workflows
- [x] 1.3 Inspect `.github/gx.toml` constraints; tighten any v0/v1 actions to `~X.Y.Z`, leave stable majors as `^X`
- [x] 1.4 Run `gx tidy`; confirm zero diff against workflow files
- [x] 1.5 Run `gx lint`; confirm zero findings

## 2. Wire up CI lint gate

- [x] 2.1 Add a `gx_lint` job to `.github/workflows/build.yml` (deviation: ci.yml only triggers on push; build.yml is the PR-time workflow). Runs on `pull_request` via existing trigger.
- [x] 2.2 Install `gx` in the job using `jaxxstorm/action-install-gh-release@6096f2a2bbfee498ced520b6922ac2c06e990ed2 # v2.1.0`, pointing at `gmeligio/gx` tag `v0.7.1` with archive digest `6632843410c877c43aa8936eb757d8b0ddcb5940402203914543ef8a9cf8ecd9`.
- [x] 2.3 Run `gx lint` as the job step with `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to avoid the 60 req/h anonymous rate limit.
- [ ] 2.4 Open a draft PR that intentionally edits a workflow SHA without rerunning `gx tidy`; confirm `gx-lint` fails
- [ ] 2.5 Run `gx tidy` on the same PR; confirm `gx-lint` passes

## 3. Keep Renovate-driven PRs in sync

- [x] 3.1 Decided: skip the `postUpgradeTasks` route (3.2/3.3) — the GitHub-hosted Mend Renovate app does not permit `postUpgradeTasks` without org-level allowlisting, so the fallback workflow is the more reliable mechanism and works for any PR (Renovate or human) that drifts the lock.
- [~] 3.2 Skipped — see 3.1.
- [~] 3.3 Skipped — see 3.1.
- [x] 3.4 Added `.github/workflows/gx-tidy.yml` triggered on `pull_request` (paths `.github/workflows/**`, `.github/gx.toml`, `.github/gx.lock`). Uses the `VERIFIED_COMMIT_ID`/`VERIFIED_COMMIT_KEY` GitHub App (same one used by `tag.yml`/`changelog.yml`/`release.yml`/`update_version.yml`) to push the fixup commit. Skips PRs from forks via `if: head.repo.full_name == github.repository`.
- [ ] 3.5 Open a test Renovate-style PR that bumps a single action SHA; confirm the lock is updated within the same PR before merge.

## 4. Documentation

- [x] 4.1 Add a "Editing GitHub Actions workflows" section to `docs/contributing.md` explaining the `gx tidy` local step and linking to `https://github.com/gmeligio/gx`
- [x] 4.2 Mention the `gx-lint` CI gate so contributors know what will fail their PR
- [x] 4.3 Reference the manifest format and a one-line snippet showing how to add a new action

## 5. Verification and rollout

- [x] 5.1 Run `openspec validate adopt-gx-for-actions` and resolve any findings
- [ ] 5.2 Open the implementation PR; confirm all CI jobs pass including the new `gx-lint`
- [ ] 5.3 After merge, monitor the next Renovate-driven github-actions PR; confirm `gx.lock` is updated alongside workflow SHAs
- [ ] 5.4 Document rollback steps inline in the PR description (delete `.github/gx.toml`, `.github/gx.lock`, the lint job, and any `postUpgradeTasks` block — workflows themselves remain untouched)
