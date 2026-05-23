## 1. Manifest updates

- [ ] 1.1 Add `node = "lts"` to `mise.toml` (keep the existing `cue = "0.15.0"` entry).
- [ ] 1.2 Verify locally with `mise install` that both `cue` 0.15.0 and the current Node LTS resolve and install on Linux.

## 2. Action manifest: add `jdx/mise-action`

- [ ] 2.1 Add `"jdx/mise-action" = "^4"` to the `[actions]` table in `.github/gx.toml`, preserving alphabetical order.
- [ ] 2.2 Regenerate `.github/gx.lock` using the project's lockfile-sync workflow so a new `[actions."jdx/mise-action"."v4.X.Y"]` block is recorded with the resolved commit SHA.
- [ ] 2.3 Capture the resolved SHA (e.g., `v4.X.Y` → `<sha>`) for use in step 3.

## 3. Migrate CUE-installing workflows

- [ ] 3.1 In `.github/workflows/ci.yml`, replace the `Setup CUE` step (line ~32) with `- name: Setup mise tools` / `uses: jdx/mise-action@<sha> # v4.X.Y`. Ensure the step runs after `Checkout repository` and before any consumer of `cue`.
- [ ] 3.2 In `.github/workflows/build.yml`, replace all 6 `Setup CUE` occurrences identically.
- [ ] 3.3 In `.github/workflows/update_version.yml`, replace all 10 `Setup CUE` occurrences identically.
- [ ] 3.4 Sanity-check each affected job: every step that runs `cue …` is preceded (in the same job) by exactly one `jdx/mise-action` step.

## 4. Migrate Node-installing workflows

- [ ] 4.1 In `.github/workflows/build.yml`, replace the `Setup NodeJS` step (line ~315) with `jdx/mise-action@<sha>` (or reuse the existing mise step if it already runs in this job). Remove the `node-version`, `cache`, and `cache-dependency-path` inputs.
- [ ] 4.2 In `.github/workflows/update_docs.yml`, replace the `Setup NodeJS` step (line ~20) with `jdx/mise-action@<sha>`.
- [ ] 4.3 In `.github/workflows/update_version.yml`, replace the `Setup NodeJS` step (line ~394) with `jdx/mise-action@<sha>`.
- [ ] 4.4 Confirm each `npm ci` / `npm run build` step still runs in the right `working-directory` (`docs/src`) with `node` on `$PATH`.

## 5. Action manifest: remove obsolete entries

- [ ] 5.1 Grep the repo for residual references: `grep -rn "jaxxstorm/action-install-gh-release\|actions/setup-node" .github/`. Expect zero matches.
- [ ] 5.2 Remove `"jaxxstorm/action-install-gh-release"` from `.github/gx.toml` (and any rule under `[actions.overrides]` if present).
- [ ] 5.3 Remove `"actions/setup-node"` from `.github/gx.toml`.
- [ ] 5.4 Regenerate `.github/gx.lock` to drop the corresponding `[actions."…"]` and `[resolutions."…"]` blocks for both removed actions.

## 6. Verification on the PR branch

- [ ] 6.1 Push the branch and open a PR; let `ci.yml` (test_image) run on push. Confirm it reaches `Test image` (the step beyond the original 401) and goes green.
- [ ] 6.2 Trigger `build.yml` via `workflow_dispatch` on the PR branch. Confirm all CUE-vet and docs-build steps pass.
- [ ] 6.3 Trigger `update_docs.yml` via `workflow_dispatch` on the PR branch. Confirm the docs build completes (cold `npm ci` is expected).
- [ ] 6.4 Trigger `update_version.yml` via `workflow_dispatch` on the PR branch. Confirm both CUE-using and Node-using job stages succeed.
- [ ] 6.5 Confirm the `actions-version-tracking` consistency check (gx.toml ↔ gx.lock ↔ workflow `uses:` SHAs) passes on the PR.

## 7. Archive

- [ ] 7.1 After PR merges to `main`, run `openspec archive p7-mise-action-cue-node` to move the change to `openspec/changes/archive/<date>-p7-mise-action-cue-node/` and sync the new `specs/ci-runtime-tool-versioning/spec.md` into `openspec/specs/`.
