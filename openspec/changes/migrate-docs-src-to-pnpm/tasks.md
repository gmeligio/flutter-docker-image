## 1. Pin pnpm in the mise manifest

- [x] 1.1 Pick the latest stable `pnpm` version (`pnpm view pnpm version` or https://github.com/pnpm/pnpm/releases) and record the choice in the PR description
- [x] 1.2 Add `pnpm = "<pinned-version>"` to `mise.toml` next to the existing `node = "lts"` entry
- [x] 1.3 Run `mise install` locally to confirm the pin resolves and the `pnpm` binary is available on `$PATH`

## 2. Convert `docs/src` to pnpm

- [x] 2.1 From `docs/src/`, run `pnpm import` to seed `pnpm-lock.yaml` from the existing `package-lock.json` (preserves the resolved transitive-dependency tree)
- [x] 2.2 Delete `docs/src/package-lock.json`
- [x] 2.3 Edit `docs/src/package.json` so `devEngines.packageManager.name` is `"pnpm"` (keep `onFail: "error"`); do NOT add a top-level `packageManager` field (corepack must not pick up an override)
- [x] 2.4 Verify `docs/src/.gitignore` still ignores `node_modules` (pnpm uses the same path); no change expected
- [x] 2.5 Run `pnpm install --frozen-lockfile` in `docs/src/` and confirm it exits 0 (required adding `docs/src/pnpm-workspace.yaml` with `allowBuilds.esbuild: true` to satisfy pnpm 11's strict-build-script gate)
- [x] 2.6 Run `pnpm run build` in `docs/src/` and confirm the four output files (`../../readme.md`, `../../LICENSE.md`, `../contributing.md`, `../windows.md`) regenerate without diff aside from the contributing-section update from task 4 (required rewriting the `build` script to chain `node compile.js …` calls directly instead of `pnpm run …`, because nested `pnpm` invocations resolved to the Node-bundled corepack shim which errors on `devEngines.packageManager` without a version field; `readme.md` also picked up an unrelated stale-Fastlane drift correction: 2.233.1 → 2.234.0 from `config/version.json`)

## 3. Update CI workflows

- [x] 3.1 In `.github/workflows/build.yml`, replace `npm ci --prefer-offline` with `pnpm install --frozen-lockfile` and `npm run build` with `pnpm run build` in the `working-directory: docs/src` step
- [x] 3.2 Apply the same substitution in `.github/workflows/update_docs.yml`
- [x] 3.3 Apply the same substitution in `.github/workflows/update_version.yml`
- [x] 3.4 Confirm none of the three workflows introduce `corepack`, `pnpm/action-setup`, `actions/setup-node`, or `npm i -g pnpm` — the only tool-bootstrap step in each affected job remains the existing `jdx/mise-action` step (also reordered `mise.toml` so `pnpm` is declared before `node`: mise lays the install dirs onto `$PATH` in mise.toml order, and Node ships a corepack-backed `pnpm` shim in `node/lts/bin/` that otherwise wins over the mise-pinned binary and errors on `devEngines.packageManager` without a version field)

## 4. Update contributor documentation

- [ ] 4.1 Edit `docs/src/contributing.mdx` to mention that the local docs build uses `pnpm install && pnpm run build` (under a new "Building the docs" section or appended to the existing structure, kept short)
- [ ] 4.2 Run `pnpm run contributing` (or `pnpm run build`) so `docs/contributing.md` is regenerated and matches the MDX source
- [ ] 4.3 Confirm `readme.md`, `LICENSE.md`, and `docs/windows.md` are unchanged from `main` (only `docs/contributing.md` should change)

## 5. Verify and commit

- [ ] 5.1 Run `openspec validate migrate-docs-src-to-pnpm` and confirm it reports valid
- [ ] 5.2 Run `git status` and confirm the diff is limited to: `mise.toml`, `docs/src/package.json`, `docs/src/package-lock.json` (deleted), `docs/src/pnpm-lock.yaml` (added), `docs/src/contributing.mdx`, `docs/contributing.md`, `.github/workflows/build.yml`, `.github/workflows/update_docs.yml`, `.github/workflows/update_version.yml`
- [ ] 5.3 Push the branch and open the PR; confirm `build.yml`'s docs job runs `pnpm install --frozen-lockfile` and `pnpm run build` successfully, and that the uploaded `docs-*` artifact byte-matches the committed Markdown
- [ ] 5.4 After merge to main, confirm `update_docs.yml` produces an empty commit-back (no compiled-output drift)
