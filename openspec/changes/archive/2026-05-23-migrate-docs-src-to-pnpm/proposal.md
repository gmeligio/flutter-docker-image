## Why

The `docs/src` MDX→Markdown pipeline currently uses `npm`, which sits outside the repository's established CI-runtime invariant that **every CI tool is pinned in `mise.toml` and bootstrapped via `jdx/mise-action`** (`ci-runtime-tool-versioning`). The package manager binary in use is whatever ships with the Node runtime — not a versioned, manifest-pinned tool — and the 141 KB `package-lock.json` is a second-class lockfile next to the project's overall pnpm-friendly direction. Aligning `docs/src` on `pnpm` makes the docs pipeline obey the same single-source-of-truth rule as the rest of CI: one grep against `mise.toml` answers "what package manager does CI use?".

This change passes the relevance gate because it modifies a spec-level invariant: the `ci-runtime-tool-versioning` capability currently enumerates `cue`, `node`, `gx`, and `git-cliff` as the manifest-pinned set; admitting `pnpm` extends that set and tightens the "no other install mechanism" rule to cover the package manager too.

## What Changes

- **BREAKING (for local workflow)**: Contributors building docs locally must use `pnpm`, not `npm`. The `devEngines.packageManager.name` gate in `docs/src/package.json` flips from `"npm"` to `"pnpm"` with `onFail: "error"`, so `npm install` will refuse to run.
- Add `pnpm = "<pinned>"` to `mise.toml`. `jdx/mise-action` then installs it in every job that needs it, alongside the existing `node` entry.
- Replace `docs/src/package-lock.json` with `docs/src/pnpm-lock.yaml` (seeded via `pnpm import` to preserve resolved versions).
- Update three CI steps from `npm ci --prefer-offline && npm run build` to `pnpm install --frozen-lockfile && pnpm run build`:
  - `.github/workflows/build.yml` (PR preview)
  - `.github/workflows/update_docs.yml` (push-to-main commit-back)
  - `.github/workflows/update_version.yml` (release pipeline)
- `docs/contributing.mdx` gains a brief note pointing contributors at `pnpm` for the local docs build, so the regenerated `docs/contributing.md` reflects the new toolchain.

## Capabilities

### New Capabilities

_None._ The change extends an existing capability rather than introducing a new one.

### Modified Capabilities

- `ci-runtime-tool-versioning`: Adds `pnpm` to the manifest-pinned tool set and forbids any other install mechanism (no `corepack enable`, no `npm i -g pnpm`, no `pnpm/action-setup`). Workflow steps that build `docs/src` SHALL invoke `pnpm` (not `npm`) after the `jdx/mise-action` bootstrap.

## Impact

- **Files touched**: `mise.toml`, `docs/src/package.json`, `docs/src/package-lock.json` (deleted), `docs/src/pnpm-lock.yaml` (added), `docs/src/contributing.mdx`, `docs/contributing.md` (regenerated), `.github/workflows/build.yml`, `.github/workflows/update_docs.yml`, `.github/workflows/update_version.yml`.
- **CI dependencies**: One new mise-managed tool (`pnpm`). No new GitHub Actions; no new external services.
- **Renovate**: No config change — Renovate's built-in `pnpm` manager updates `pnpm-lock.yaml` natively.
- **gx**: Out of scope — gx tracks Action SHAs; no Actions are added or removed.
- **Backwards compatibility**: Any contributor with cached muscle memory for `npm ci` in `docs/src` will see a clean `devEngines` error directing them to pnpm. The compiled output (`readme.md`, `docs/windows.md`, `LICENSE.md`, `docs/contributing.md`) is byte-identical because `mdx-to-md` and its plugins remain on the same pinned versions.
- **Post-merge expectation**: The first run of `update_docs.yml` after merge should produce an empty commit-back, confirming compiled-output parity. Any non-empty commit on that run is the signal that pnpm's resolution produced a different dependency tree and warrants follow-up. This is a passive observation, not an implementation task — the existing `update_docs.yml` (with `success-if-no-changes: true`) surfaces it automatically.
