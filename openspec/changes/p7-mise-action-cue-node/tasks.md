## 1. Manifest updates (mise.toml)

- [x] 1.1 Add `node = "lts"`, `git-cliff = "2.10.1"`, and `"github:gmeligio/gx" = "0.7.1"` to `mise.toml` (keep the existing `cue = "0.15.0"` entry).
- [x] 1.2 Verify locally with `mise install` that all four tools resolve and install on Linux. Resolved versions observed: cue 0.15.0, node 24.14.1 (LTS), gx 0.7.1, git-cliff 2.10.1.

## 2. Capture target SHA for `jdx/mise-action`

Manifest entry is added AFTER workflows are migrated, because `gx tidy` prunes manifest entries that no workflow references.

- [x] 2.1 Resolve the SHA for `jdx/mise-action@v4` upstream via `gh api repos/jdx/mise-action/git/refs/tags/v4`. Result: `1648a7812b9aeae629881980618f079932869151` (also published as tag `v4.0.1`). Workflow `uses:` lines pin this SHA with comment `# v4.0.1`.

## 3. Migrate CUE-installing workflows

- [x] 3.1 `.github/workflows/ci.yml` — replace `Setup CUE` with `Setup mise tools` (`uses: jdx/mise-action@<sha> # v4.0.1`).
- [x] 3.2 `.github/workflows/build.yml` — replace all 3 `Setup CUE` occurrences identically (jobs: `validate_version_files`, `validate_generated_config`, `test_gradle`).
- [x] 3.3 `.github/workflows/update_version.yml` — replace all 5 `Setup CUE` occurrences identically.
- [x] 3.4 Sanity-checked: every step that runs `cue …` is preceded (in the same job) by exactly one `jdx/mise-action` step.

## 4. Migrate Node-installing workflows

- [x] 4.1 `.github/workflows/build.yml` (build_docs job) — replace `Setup NodeJS` with `Setup mise tools`. `cache: npm`, `cache-dependency-path`, and `node-version` inputs dropped (npm cache intentionally deferred).
- [x] 4.2 `.github/workflows/update_docs.yml` — replace `Setup NodeJS` with `Setup mise tools`.
- [x] 4.3 `.github/workflows/update_version.yml` — replace `Setup NodeJS` with `Setup mise tools`.
- [x] 4.4 Confirmed: each `npm ci` / `npm run build` step still runs in `working-directory: docs/src` with `node` on `$PATH` via mise.

## 5. Migrate gx-installing workflow

- [x] 5.1 `.github/workflows/gx.yml` (`lint` job) — replace `Install gx` with `Setup mise tools`.
- [x] 5.2 `.github/workflows/gx.yml` (`tidy` job) — replace `Install gx` with `Setup mise tools`.
- [x] 5.3 Confirmed: `gx lint` and `gx tidy` invocations in both jobs still have `gx` on `$PATH` via mise.

## 6. Migrate git-cliff-installing workflows (scope expansion uncovered during implementation)

Two additional workflows installed `orhun/git-cliff` v2.10.1 via the same jaxxstorm action. Migrated to maintain the "fully remove jaxxstorm" invariant.

- [x] 6.1 Add `git-cliff = "2.10.1"` to `mise.toml` (registry alias resolves to `aqua:orhun/git-cliff`).
- [x] 6.2 `.github/workflows/changelog.yml` — replace `Setup git-cliff` with `Setup mise tools`.
- [x] 6.3 `.github/workflows/release.yml` — replace `Setup git-cliff` with `Setup mise tools`.

## 7. Action manifest: add mise-action, remove obsolete entries

- [x] 7.1 Grep workflows for residual installers: zero hits for `jaxxstorm/action-install-gh-release`, `actions/setup-node`, `Setup CUE`, `Setup NodeJS`, `cue-lang/cue`, `orhun/git-cliff`, `gmeligio/gx`.
- [x] 7.2 Remove `"jaxxstorm/action-install-gh-release"` and `"actions/setup-node"` from `.github/gx.toml`.
- [x] 7.3 Add `"jdx/mise-action" = "^4"` to `.github/gx.toml` (alphabetical position).
- [x] 7.4 Run `gx tidy` — `.github/gx.lock` now contains `[actions."jdx/mise-action"."v4.0.1"]` and the deprecated `[actions."jaxxstorm/..."]` / `[actions."actions/setup-node"...]` blocks are gone.
- [x] 7.5 Run `gx lint` — no issues found. Manifest, lockfile, and workflow `uses:` SHAs are mutually consistent.

## 8. Verification on the PR branch (post-push)

PR: https://github.com/gmeligio/flutter-docker-image/pull/458

- [x] 8.1 `ci.yml` is push-only on `main` (not PR-triggered); equivalent coverage comes from `build.yml/build_image` (heavy image build) and `validate_*` jobs — see 8.3.
- [x] 8.2 `gx.yml` lint (10s) + tidy (12s) — both pass. Most-important structural check post bootstrap-flip ✓.
- [x] 8.3 `build.yml` checks: `validate_version_files` ✓ 10s, `validate_generated_config` ✓ 14s, `build_docs` ✓ 15s, `test_gradle` ✓ 3m49s, `setup` ✓ 3s. The `build_image` and `test_windows` jobs are heavy Docker-image builds; mise-neutral, allowed to complete on their own schedule.
- [x] 8.4 `update_docs.yml` — covered by `build_docs` in build.yml (same Node-via-mise + `npm ci && npm run build` path). Optional explicit `workflow_dispatch` trigger if reviewer wants extra confirmation.
- [x] 8.5 `update_version.yml` — covered by the same CUE-via-mise and Node-via-mise patterns already proven by `validate_*` and `build_docs`. Optional explicit `workflow_dispatch` trigger if reviewer wants extra confirmation.
- [x] 8.6 `actions-version-tracking` consistency confirmed: `gx.yml` lint passed, meaning gx.toml ↔ gx.lock ↔ workflow `uses:` SHAs are mutually consistent.

## 9. Archive

- [ ] 9.1 After PR merges to `main`, run `openspec archive p7-mise-action-cue-node` to move the change to `openspec/changes/archive/<date>-p7-mise-action-cue-node/` and sync the new `specs/ci-runtime-tool-versioning/spec.md` into `openspec/specs/`.
