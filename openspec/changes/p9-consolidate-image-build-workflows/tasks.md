## 1. Add workflow and job display names (Commit A — no id changes)

- [x] 1.1 For every file in `.github/workflows/`, add a top-level `name:` in Title Case if absent (e.g. `Build image`, `CI`, `Windows`, `Release`, `Scorecard`, `gx`). Leave files that already have one.
- [x] 1.2 For every job in every workflow, add a `name:` key as a Title Case verb phrase (e.g. `setup` → `name: Read latest release`, `build_image` → `name: Build and push image`, `test_image` → `name: Test image`, `scan_image` → `name: Scan image`, `validate_version_files` → `name: Validate version files`, `release_android` → `name: Release Android`, `update_description` → `name: Update Docker Hub description`, `record_image` → `name: Record image in Scout`, `create_github_release` → `name: Create GitHub release`). The `name:` is the display label; the `jobs.<id>:` key is renamed separately in §2.
- [x] 1.3 This commit changes only display names — no `jobs.<id>:` key changes, so no pinned check breaks yet. Confirm CI parses every file.

## 2. Rename job ids (the `jobs.<id>:` YAML keys) to kebab-case (Commit B)

- [x] 2.1 Enumerate every job id across all workflows (e.g. `build_image`, `test_image`, `scan_image`, `test_gradle`, `validate_version_files`, `validate_generated_config`, `build_docs`, `release_android`, `release_windows`, `update_description`, `record_image`, `create_github_release`, `create_git_tag`, `changelog`). Map each to its kebab-case form.
- [x] 2.2 Rename each `jobs.<id>:` key to kebab-case.
- [x] 2.3 Update every `needs:` list and every `${{ needs.<id>.outputs.* }}` expression to the new ids, in the same commit.
- [x] 2.4 Grep all of `.github/workflows/` and `script/` for `github.job` and `needs\.`; confirm no reference points to an old id.

## 3. Merge changelog + tag into prepare-release (Commit C)

- [x] 3.1 Create `.github/workflows/prepare-release.yml` with `name: Prepare release`, trigger `on: push: { branches: [main], paths: [config/version.json] }` plus `workflow_dispatch` — the SAME trigger as today's `changelog.yml` (NOT the `changelog.md` trigger from `tag.yml`).
- [x] 3.2 Job `update-changelog` (`name: update-changelog`): lift the steps from `changelog.yml`'s `changelog` job verbatim (harden-runner, checkout with fetch-depth 0 + tags, mise, setEnvironmentVariables, git-cliff, App-token, commit-and-push).
- [x] 3.3 Job `create-tag` (`name: create-tag`) with `needs: update-changelog`: lift the steps from `tag.yml`'s `create_git_tag` job (App-token, setEnvironmentVariables, createGitTag.js). The `needs:` edge replaces the `changelog.md` push trigger.
- [x] 3.4 `git rm` `changelog.yml` and `tag.yml`.

## 4. Rename underscore workflow files (Commit D)

- [x] 4.1 `git mv .github/workflows/update_docs.yml .github/workflows/update-docs.yml`; update its top-level `name:` if needed; grep for references to the old filename and update.
- [x] 4.2 `git mv .github/workflows/cleanup_pr_image.yml .github/workflows/cleanup-pr-image.yml`; same.
- [x] 4.3 Do NOT rename `update_version.yml` — deferred until `p12-symmetric-platform-updates` archives (collision with its in-flight internal refactor).
- [x] 4.4 Keep renames in their own commit so `git log --follow` traces history.

## 5. Update external references and repo settings

- [ ] 5.1 Update any `README.md` / `readme.md` workflow-filename references or badges that point to renamed files.
- [ ] 5.2 Coordinate with `p10`: update `.github/rulesets/main.json` comments / check-name lists that reference `changelog.yml` or `tag.yml`.
- [ ] 5.3 **Before merge**: enumerate branch-protection required status checks (ruleset `1959230` / Settings → Branches) and update any pinned `<workflow> / <job-name>` whose job id or name changed. Skipping this blocks the post-merge run.
- [ ] 5.4 Update any `openspec/specs/*/spec.md` links that reference renamed workflows by filename.

## 6. Verify

- [ ] 6.1 `gx lint` is green (no action-pin drift introduced).
- [ ] 6.2 Repo-wide assert: no `_` in any `.github/workflows/*.yml` filename except `update_version.yml`; no dangling `needs.<old_id>` or `github.job` reference (grep).
- [ ] 6.3 In a draft PR, push a no-op `config/version.json` edit on a branch and `workflow_dispatch` `prepare-release.yml`; confirm `update-changelog` → `create-tag` runs and the new tag triggers `release.yml` — full chain works.
- [ ] 6.4 `workflow_dispatch` each renamed workflow (`update-docs`, `cleanup-pr-image`) once; confirm it runs under its new filename and appears in the Actions UI.
- [ ] 6.5 Confirm Scorecard scan still passes after merge (no regressions from the new `prepare-release.yml`).
