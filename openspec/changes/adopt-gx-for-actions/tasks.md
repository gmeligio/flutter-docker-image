## 1. Generate manifest and lock locally

- [ ] 1.1 Install `gx` locally (`brew install gmeligio/tap/gx` or `cargo install gx`) and verify with `gx --version`
- [ ] 1.2 Run `gx init` at the repo root; confirm it generates `.github/gx.toml` and `.github/gx.lock` from existing SHA-pinned workflows
- [ ] 1.3 Inspect `.github/gx.toml` constraints; tighten any v0/v1 actions to `~X.Y.Z`, leave stable majors as `^X`
- [ ] 1.4 Run `gx tidy`; confirm zero diff against workflow files
- [ ] 1.5 Run `gx lint`; confirm zero findings

## 2. Wire up CI lint gate

- [ ] 2.1 Add a `gx-lint` job to `.github/workflows/ci.yml` that runs on `pull_request`
- [ ] 2.2 Install `gx` in the job using `jaxxstorm/action-install-gh-release@<sha> # v2`, pointing at `gmeligio/gx` and pinning to a specific release version
- [ ] 2.3 Run `gx lint` as the job step; pass `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` only if lint requires API access (verify in 1.5)
- [ ] 2.4 Open a draft PR that intentionally edits a workflow SHA without rerunning `gx tidy`; confirm `gx-lint` fails
- [ ] 2.5 Run `gx tidy` on the same PR; confirm `gx-lint` passes

## 3. Keep Renovate-driven PRs in sync

- [ ] 3.1 Verify whether the GitHub-hosted Renovate app permits `postUpgradeTasks` for this repo; if blocked, skip to 3.4
- [ ] 3.2 If permitted: add a `postUpgradeTasks` block to `.github/renovate.json` that matches `github-actions` PRs and runs `gx tidy`, listing `.github/gx.toml` and `.github/gx.lock` under `fileFilters`
- [ ] 3.3 If permitted: install `gx` in the Renovate runner (typically via `allowedPostUpgradeCommands` self-hosted config) — document the exact mechanism in `docs/contributing.md`
- [ ] 3.4 Fallback workflow: add `.github/workflows/gx-tidy.yml` triggered on `pull_request` with paths `.github/workflows/**`; run `gx tidy` and push a fixup commit when the lock drifts. Use `actions/create-github-app-token@<sha>` (already pinned in repo) to authenticate the push
- [ ] 3.5 Open a test Renovate-style PR that bumps a single action SHA; confirm the lock is updated within the same PR before merge

## 4. Documentation

- [ ] 4.1 Add a "Editing GitHub Actions workflows" section to `docs/contributing.md` explaining the `gx tidy` local step and linking to `https://github.com/gmeligio/gx`
- [ ] 4.2 Mention the `gx-lint` CI gate so contributors know what will fail their PR
- [ ] 4.3 Reference the manifest format and a one-line snippet showing how to add a new action

## 5. Verification and rollout

- [ ] 5.1 Run `openspec validate adopt-gx-for-actions` and resolve any findings
- [ ] 5.2 Open the implementation PR; confirm all CI jobs pass including the new `gx-lint`
- [ ] 5.3 After merge, monitor the next Renovate-driven github-actions PR; confirm `gx.lock` is updated alongside workflow SHAs
- [ ] 5.4 Document rollback steps inline in the PR description (delete `.github/gx.toml`, `.github/gx.lock`, the lint job, and any `postUpgradeTasks` block — workflows themselves remain untouched)
