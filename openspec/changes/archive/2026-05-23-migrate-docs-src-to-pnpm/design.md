## Context

`docs/src/` compiles MDX into the committed Markdown surfaces a reader sees on GitHub and Docker Hub (`readme.md`, `LICENSE.md`, `docs/contributing.md`, `docs/windows.md`). It's the only Node project in the repo and is invoked from three CI workflows: `build.yml` (PR preview artifact), `update_docs.yml` (push-to-main commit-back), and `update_version.yml` (release pipeline).

The repository recently consolidated all CI runtime tools behind a single `mise.toml` manifest (archived change `2026-05-23-p7-mise-action-cue-node`). Today `mise.toml` pins `cue`, `git-cliff`, `node`, and `gx`; every workflow bootstraps them with one `jdx/mise-action@<sha>` step. The `ci-runtime-tool-versioning` spec enforces this as an invariant. The npm binary that workflows currently use is whichever one happens to ship with Node `lts` — i.e., unpinned. Switching the docs build to `pnpm` and pinning that pnpm in `mise.toml` brings the package manager into the same invariant.

`docs/src/package.json` already declares a `devEngines` block with `packageManager.name = "npm"` and `onFail: "error"` — this gate would refuse pnpm today, so the migration is also the act of flipping that gate.

## Goals / Non-Goals

**Goals:**

- One source of truth for the docs-build package manager: `mise.toml` (pinned, exact version).
- No new GitHub Actions added; no `pnpm/action-setup`, no `corepack enable` step.
- Byte-identical compiled output (`readme.md`, etc.) — this is a toolchain swap, not a content change.
- Local-dev parity: a contributor running `pnpm install && pnpm run build` from `docs/src` produces the same output CI produces.
- Renovate continues to keep the lockfile fresh with zero config changes.

**Non-Goals:**

- Migrating any other directory (there is no other Node project in the repo).
- Bumping any `docs/src` dependency version — every package in `package.json` stays at its current floor.
- Changing the compile script (`compile.js`) or the MDX → MD pipeline behavior.
- Introducing pnpm workspaces or any multi-package layout.

## Decisions

### Decision 1: Install pnpm via mise (not corepack, not `pnpm/action-setup`)

**Choice**: Add `pnpm = "<pinned>"` to `mise.toml` and let `jdx/mise-action` install it.

**Why**: The `ci-runtime-tool-versioning` spec already mandates that every CI runtime tool comes from `mise.toml`. Using corepack would put the pnpm version inside `docs/src/package.json` (`packageManager: "pnpm@…"`) — a second source of truth, and one that the spec's "no other install mechanism" clause would have to carve out an exception for. Using `pnpm/action-setup` adds a third-party Action that gx would need to track and that exists nowhere else in the workflow set.

**Alternatives considered:**

- **Corepack** (`corepack enable`): Officially bundled with Node, but corepack signature-verification changes through 2025 produced sporadic CI breakage in other projects; and version drift between `packageManager:` in `package.json` and what mise resolves for `node` would be possible.
- **`pnpm/action-setup@v4`**: Battle-tested, but adds a fifth way to install a CI tool and a new SHA for gx to pin and Renovate to chase. Loses the "one grep tells you the version" property.

### Decision 2: Pin pnpm to an exact version, not `"latest"`

**Choice**: Pin to a concrete version (e.g., `pnpm = "9.15.0"` at implementation time — implementer picks the latest stable at the moment).

**Why**: Mirrors every other entry in `mise.toml` (`cue = "0.15.0"`, `git-cliff = "2.10.1"`, `"github:gmeligio/gx" = "0.7.1"`). The one exception today, `node = "lts"`, is a deliberate choice for the broader Node ecosystem; the package-manager pin should be reproducible to the build-tool level, not just the language level.

### Decision 3: Seed `pnpm-lock.yaml` via `pnpm import` from the existing `package-lock.json`

**Choice**: Run `pnpm import` once in `docs/src/` before deleting `package-lock.json`. Commit the resulting `pnpm-lock.yaml`.

**Why**: Preserves the exact resolved-version graph (down to transitive deps) the project ships with today, removing the "did some sub-dep version float?" question from review. A clean `pnpm install` from scratch would also work and would resolve to the latest semver-compatible versions, but that conflates "swap the package manager" with "refresh the lockfile" — two separable concerns. Renovate's regular schedule will handle drift afterwards.

**Alternative considered:** `rm package-lock.json && pnpm install` to get a fresh resolution. Rejected to keep the diff reviewable: any compiled-output change can then only come from the pnpm install algorithm itself, not from a dependency bump.

### Decision 4: Use `pnpm install --frozen-lockfile` in CI (not `pnpm install --offline` or `pnpm ci`)

**Choice**: `pnpm install --frozen-lockfile` in all three workflows. (There is no `pnpm ci` command — the canonical CI flag is `--frozen-lockfile`.)

**Why**: Matches the semantics of `npm ci --prefer-offline` that we are replacing: refuse to install if the lockfile is out of date, prefer cached tarballs when available. `--offline` would be stricter than the existing behavior and could cause spurious cold-cache failures.

### Decision 5: Update `devEngines.packageManager.name` to `"pnpm"`, keep `onFail: "error"`

**Choice**: Flip the existing gate from npm to pnpm and keep the hard-fail policy.

**Why**: The gate is what produces a clear "you are using the wrong package manager" error for local contributors. Flipping it to pnpm preserves that signal. Loosening to `onFail: "warn"` would silently let `npm install` run and produce a stray `package-lock.json` next to `pnpm-lock.yaml`, which is worse than the status quo.

### Decision 6: Approve `esbuild`'s native postinstall via `docs/src/pnpm-workspace.yaml`

**Choice**: Commit a small `docs/src/pnpm-workspace.yaml` containing `allowBuilds.esbuild: true`. No actual workspace is declared — the file exists only to carry pnpm's per-package build-script allowlist.

**Why**: pnpm 11 refuses to run dependency postinstalls unless they appear in an explicit allowlist. `mdx-to-md` transitively depends on `esbuild`, which compiles a native binary in its postinstall; without approval, `pnpm install --frozen-lockfile` exits 0 but `pnpm run build` fails because the esbuild binary is missing. pnpm 11 deliberately moved this setting out of `package.json#pnpm` and ignores it in `.npmrc`, so `pnpm-workspace.yaml` is the only home that works.

**Alternatives considered:** keep the setting in `package.json#pnpm` (silently ignored in pnpm 11 with a warning), or pin a lower pnpm major that still honors the old location. Both were rejected because they trade today's clean error for tomorrow's drift — every new pnpm-11-or-later contributor would hit the silent ignore, and downgrading the pnpm major contradicts Decision 2.

### Decision 7: List `pnpm` before `node` in `mise.toml`

**Choice**: Declare tools in this order: `cue`, `git-cliff`, `pnpm`, `node`, `gx`.

**Why**: `mise` lays each tool's install directory onto `$PATH` in the order they appear in `mise.toml`. Node ships a corepack-backed `pnpm` shim at `node/lts/bin/pnpm`. If `node` is declared before `pnpm`, the corepack shim wins over the mise-pinned binary. Corepack then reads `devEngines.packageManager` and errors because we deliberately do not pin a version there (Decision 1 — single source of truth in `mise.toml`). Reordering puts the mise-pinned `pnpm/<version>/pnpm` first.

**Alternative considered:** add `version` to `devEngines.packageManager` so corepack accepts the spec. Rejected because it creates a second source of truth for the pnpm version (Renovate manages `pnpm-lock.yaml` but not `devEngines.packageManager.version`, so drift would be inevitable).

## Risks / Trade-offs

- **Risk**: Compiled Markdown drift after the swap. → **Mitigation**: Run `pnpm import` (Decision 3) so the resolved tree is byte-identical; `pnpm run build` locally before pushing; the `update_docs.yml` commit-back diff will be empty on push-to-main if outputs are stable. Reviewer must verify zero changes to `readme.md`, `LICENSE.md`, `docs/contributing.md`, `docs/windows.md` aside from the new "use pnpm" mention.
- **Risk**: pnpm's non-flat `node_modules` exposes a phantom-dependency in `compile.js`. → **Mitigation**: `compile.js` imports only declared deps (`mdx-to-md`, `remark-gfm`, `remark-toc`) per audit; local `pnpm run build` in the worktree will surface anything missed before CI.
- **Risk**: First CI run on a PR pulls a cold pnpm store and runs slower than npm. → **Mitigation**: mise caches the pnpm binary in `~/.local/share/mise`, and `pnpm install --frozen-lockfile` benefits from pnpm's content-addressable store on subsequent runs. Net change to wall-clock CI is expected to be sub-second either way for a 6-direct-dep project.
- **Risk**: Contributor confusion from the package-manager swap. → **Mitigation**: The `devEngines` error is loud and actionable ("This project requires pnpm"). Update `docs/src/contributing.mdx` so the regenerated `docs/contributing.md` documents the new local command.
- **Trade-off**: One more line in `mise.toml`. Worth it for the invariant. The same trade-off was made for `cue`, `git-cliff`, and `gx`.

## Automated Test Strategy

This change has no production-runtime surface — it ships no code that runs in the published Docker images, no scripts that users execute. Verification is structural and CI-pipeline:

- **Static checks** (PR-time):
  - `pnpm install --frozen-lockfile` exits 0 in `docs/src/` on a fresh checkout (covered by all three modified workflows — if the lockfile is malformed or out of sync, every CI job fails).
  - `pnpm run build` exits 0 and produces the four target Markdown files.
  - The PR diff for `readme.md`, `LICENSE.md`, `docs/contributing.md`, `docs/windows.md` is limited to the documented contributing-section addition; no unexplained changes.
- **Workflow assertions** (existing):
  - `build.yml` already uploads the compiled docs as an artifact (`docs-${{ github.event.pull_request.number }}`); reviewers can download and diff against the committed copies if anything looks off.
  - `update_docs.yml` posts a `success-if-no-changes: true` commit on push to main — a non-empty commit there after the migration would be the signal that the compiled output drifted.
- **Spec invariant** (manual review): The `ci-runtime-tool-versioning` invariant is enforced at PR review (no `corepack enable`, no `pnpm/action-setup`, no `npm i -g pnpm` introduced anywhere). No automated linter exists for this today; the existing spec text is the contract.

No new test infrastructure is introduced. The critical path is `pnpm install --frozen-lockfile && pnpm run build` running successfully in the three workflows on the first PR after the migration.

## Observability

Failure modes and how they surface:

- **Lockfile-out-of-date**: `pnpm install --frozen-lockfile` exits non-zero with a clear "Cannot install with frozen-lockfile because pnpm-lock.yaml is not up to date" message. The CI job fails loudly in all three workflows.
- **mise install of pnpm fails**: `jdx/mise-action` step fails before any docs-build step runs; existing CI surface (job summary, red X on PR check) handles this.
- **devEngines mismatch on local install**: `pnpm` and `npm` both honor `devEngines.packageManager.name` with `onFail: "error"`. A contributor running `npm install` sees a hard error explaining the project requires pnpm.
- **Compiled-output drift**: Caught either at PR review (diff in `readme.md` / `docs/*.md`) or by `update_docs.yml` producing a non-empty commit-back on main. Both surfaces are existing — no new logging or alerting needed.
- **Silent-failure risk**: The only realistic silent-failure path is `pnpm run build` exiting 0 but writing partial output. `compile.js` uses `await writeFile(…)` with no try/catch, so a write error throws and the script exits non-zero; no change needed.

No new logs, metrics, or dashboards are introduced. The existing CI job-status surface is sufficient.

## Migration Plan

1. Land the change as one PR (small enough to bundle).
2. The PR is itself the first run of the new toolchain: `build.yml` will invoke the new pnpm steps against the new lockfile. A green CI run is the smoke test.
3. Once merged, `update_docs.yml` runs on push to main; an empty commit-back (no changes) confirms compiled-output parity.

**Rollback**: Revert the merge commit. `package-lock.json` reappears, `mise.toml` loses the `pnpm` entry, workflows go back to `npm ci`. No external state is mutated by this change, so revert is sufficient.

## Open Questions

None. Concrete pnpm version is picked by the implementer at apply-time (latest stable at the moment, per Decision 2).
