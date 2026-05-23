## 1. Manifest updates

- [x] 1.1 Add `node = "lts"` and `"github:gmeligio/gx" = "0.7.1"` to `mise.toml` (keep the existing `cue = "0.15.0"` entry).
- [x] 1.2 Verify locally with `mise install` that `cue` 0.15.0, the current Node LTS, and `gx` 0.7.1 resolve and install on Linux.

## 2. Action manifest: add `jdx/mise-action`

- [ ] 2.1 Add `"jdx/mise-action" = "^4"` to the `[actions]` table in `.github/gx.toml`, preserving alphabetical order.
- [ ] 2.2 Regenerate `.github/gx.lock` using `gx tidy` so a new `[actions."jdx/mise-action"."v4.X.Y"]` block is recorded with the resolved commit SHA.
- [ ] 2.3 Capture the resolved SHA (e.g., `v4.X.Y` → `<sha>`) for use in steps 3, 4, and 5.

## 3. Migrate CUE-installing workflows

- [ ] 3.1 In `.github/workflows/ci.yml`, replace the `Setup CUE` step with `- name: Setup mise tools` / `uses: jdx/mise-action@<sha> # v4.X.Y`. Ensure the step runs after `Checkout repository` and before any consumer of `cue`.
- [ ] 3.2 In `.github/workflows/build.yml`, replace all 6 `Setup CUE` occurrences identically.
- [ ] 3.3 In `.github/workflows/update_version.yml`, replace all 10 `Setup CUE` occurrences identically.
- [ ] 3.4 Sanity-check each affected job: every step that runs `cue …` is preceded (in the same job) by exactly one `jdx/mise-action` step.

## 4. Migrate Node-installing workflows

- [ ] 4.1 In `.github/workflows/build.yml`, replace the `Setup NodeJS` step with `jdx/mise-action@<sha>` (or merge into the existing mise step if one already runs earlier in the same job). Remove the `node-version`, `cache`, and `cache-dependency-path` inputs.
- [ ] 4.2 In `.github/workflows/update_docs.yml`, replace the `Setup NodeJS` step with `jdx/mise-action@<sha>`.
- [ ] 4.3 In `.github/workflows/update_version.yml`, replace the `Setup NodeJS` step with `jdx/mise-action@<sha>`.
- [ ] 4.4 Confirm each `npm ci` / `npm run build` step still runs in the right `working-directory` (`docs/src`) with `node` on `$PATH`.

## 5. Migrate gx-installing workflow

- [ ] 5.1 In `.github/workflows/gx.yml`, replace the `Install gx` step in the `lint` job with `jdx/mise-action@<sha>`. The step's runtime cost is now bootstrapping `mise` + installing `gx` from `mise.toml`.
- [ ] 5.2 In the same file, replace the `Install gx` step in the `tidy` job identically.
- [ ] 5.3 Confirm `gx lint` and `gx tidy` (or `gx --version`) commands in both jobs still have `gx` on `$PATH`.

## 6. Action manifest: remove obsolete entries

- [ ] 6.1 Grep the repo for residual references: `grep -rn "jaxxstorm/action-install-gh-release\|actions/setup-node" .github/`. Expect zero matches.
- [ ] 6.2 Remove `"jaxxstorm/action-install-gh-release"` from `.github/gx.toml` (and any rule under `[actions.overrides]` if present).
- [ ] 6.3 Remove `"actions/setup-node"` from `.github/gx.toml`.
- [ ] 6.4 Run `gx tidy` to drop the corresponding `[actions."…"]` and `[resolutions."…"]` blocks from `.github/gx.lock`.

## 7. Verification on the PR branch

- [ ] 7.1 Push the branch and open a PR; let `ci.yml` (test_image) run on push. Confirm it reaches `Test image` (the step beyond the original 401) and goes green.
- [ ] 7.2 Confirm `gx.yml` (lint + tidy jobs) run successfully on the PR — this is the workflow most affected by the bootstrap-flip.
- [ ] 7.3 Trigger `build.yml` via `workflow_dispatch` on the PR branch. Confirm all CUE-vet and docs-build steps pass.
- [ ] 7.4 Trigger `update_docs.yml` via `workflow_dispatch` on the PR branch. Confirm the docs build completes (cold `npm ci` is expected).
- [ ] 7.5 Trigger `update_version.yml` via `workflow_dispatch` on the PR branch. Confirm both CUE-using and Node-using job stages succeed.
- [ ] 7.6 Confirm the `actions-version-tracking` consistency check (gx.toml ↔ gx.lock ↔ workflow `uses:` SHAs) passes on the PR — verified by `gx.yml` itself going green.

## 8. Archive

- [ ] 8.1 After PR merges to `main`, run `openspec archive p7-mise-action-cue-node` to move the change to `openspec/changes/archive/<date>-p7-mise-action-cue-node/` and sync the new `specs/ci-runtime-tool-versioning/spec.md` into `openspec/specs/`.
