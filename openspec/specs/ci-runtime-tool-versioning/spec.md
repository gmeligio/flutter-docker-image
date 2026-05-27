# ci-runtime-tool-versioning Specification

## Purpose

Establishes `mise.toml` as the single source of truth for CI runtime tool versions, consumed by every workflow via `jdx/mise-action`. Covers where versions live, how they reach `$PATH` in each job, and the invariant that no workflow may install these tools by any other mechanism. The desktop user this serves is the CI engineer or maintainer who needs a single, authoritative answer to "what version of tool X does CI run with?".
## Requirements
### Requirement: Single-source version manifest for CI runtime tools

The repository SHALL pin every CI runtime tool version (currently `cue`, `node`, `pnpm`, `gx`, `git-cliff`, and `container-structure-test`) in `mise.toml` at the repository root. No workflow under `.github/workflows/` or composite action under `.github/actions/` may install these tools by any other mechanism (e.g., `jaxxstorm/action-install-gh-release`, `actions/setup-node`, `pnpm/action-setup`, `corepack enable`, hand-rolled `curl | tar`, `npm i -g pnpm`, or wrapper Actions like `plexsystems/container-structure-test-action`).

**Experience context:** A CI engineer or maintainer asking *"what version of cue does CI run with?"* (or `node`, `pnpm`, `gx`, `git-cliff`, `container-structure-test`) reads exactly one file — `mise.toml` — and gets a single, authoritative answer. The package manager used by the `docs/src` MDX→Markdown build is part of this answer: before this requirement was extended to cover `pnpm`, the docs build used whichever `npm` happened to ship with the resolved `node`, leaving the package-manager version effectively unpinned. The Android smoke-test runner is part of this answer too: before this requirement was extended to cover `container-structure-test`, the test binary was vendored by a third-party Action whose own pinning lived in `gx.toml`/`gx.lock` — a second source of truth divergent from `mise.toml`.

#### Scenario: Maintainer looks up the pinned CUE version

- **GIVEN** a maintainer wants to know which CUE version CI uses
- **WHEN** they `grep cue mise.toml`
- **THEN** exactly one entry is returned, with a concrete version (e.g., `cue = "0.15.0"`)
- **AND** no other file in `.github/workflows/` or `.github/actions/` contains a literal CUE version or release tag

#### Scenario: Maintainer looks up the pinned Node version

- **GIVEN** a maintainer wants to know which Node version CI uses
- **WHEN** they `grep node mise.toml`
- **THEN** exactly one entry is returned (e.g., `node = "lts"` or a concrete major)
- **AND** no workflow file contains a `node-version:` input or hand-rolled Node install

#### Scenario: Maintainer looks up the pinned pnpm version

- **GIVEN** a maintainer wants to know which `pnpm` version CI uses for the `docs/src` build
- **WHEN** they `grep pnpm mise.toml`
- **THEN** exactly one entry is returned, with a concrete version (e.g., `pnpm = "9.15.0"`)
- **AND** no workflow file or `docs/src/package.json` field installs `pnpm` via `corepack enable`, `pnpm/action-setup`, `npm i -g pnpm`, or any other mechanism
- **AND** `docs/src/package.json` does not contain a `packageManager` field that would let corepack pick a different version

#### Scenario: Maintainer looks up the pinned gx version

- **GIVEN** a maintainer wants to know which `gx` version CI uses
- **WHEN** they `grep gx mise.toml`
- **THEN** exactly one entry is returned (e.g., `"github:gmeligio/gx" = "0.7.1"`)
- **AND** no workflow file contains a literal `gx` version, release tag, or release digest

#### Scenario: Maintainer looks up the pinned container-structure-test version

- **GIVEN** a maintainer wants to know which `container-structure-test` version CI uses
- **WHEN** they `grep container-structure-test mise.toml`
- **THEN** exactly one entry is returned (e.g., `"github:GoogleContainerTools/container-structure-test[exe=container-structure-test-linux-amd64]" = "1.22.1"`)
- **AND** no workflow file contains a reference to `plexsystems/container-structure-test-action` or any other wrapper that vendors the binary
- **AND** `.github/gx.toml` and `.github/gx.lock` do not contain a `plexsystems/container-structure-test-action` entry

#### Scenario: Drift attempt is blocked at review

- **GIVEN** a PR adds a step `uses: actions/setup-node@<sha>`, `uses: pnpm/action-setup@<sha>`, `uses: jaxxstorm/action-install-gh-release@<sha>`, `uses: plexsystems/container-structure-test-action@<sha>`, or a `run: corepack enable` / `run: npm i -g pnpm` line to any workflow
- **WHEN** the PR is reviewed
- **THEN** the change is rejected and re-implemented using `jdx/mise-action@<pinned>` plus the appropriate `mise.toml` pin
- **AND** the rationale references this requirement

### Requirement: Workflows bootstrap tools via `jdx/mise-action`

Every job that needs `cue`, `node`, `pnpm`, `gx`, `git-cliff`, or `container-structure-test` on `$PATH` SHALL bootstrap them with a single step `uses: jdx/mise-action@<pinned-major>` placed before any step that invokes those tools. The step SHALL rely on `mise.toml` for version resolution and SHALL NOT pass an explicit `tools:` input that contradicts `mise.toml`.

**Experience context:** A maintainer adding a new CI job that needs `cue`, `node`, the docs-build toolchain, or the image smoke-test runner writes one boilerplate step (the same step every other job uses) and gets the project-pinned version. They never re-derive a download URL, copy a SHA digest, or add a second tool-installer action.

#### Scenario: New job needing CUE

- **GIVEN** a new workflow job needs to run `cue vet`
- **WHEN** the job is authored
- **THEN** it contains exactly one tool-bootstrap step `uses: jdx/mise-action@v4` before the `cue` invocation
- **AND** no `with:` input overrides `cue`'s version

#### Scenario: New job needing the docs-build toolchain

- **GIVEN** a new workflow job needs to run `pnpm install --frozen-lockfile && pnpm run build` in `docs/src`
- **WHEN** the job is authored
- **THEN** it contains exactly one `uses: jdx/mise-action@v4` step before any `pnpm` invocation
- **AND** `node` and `pnpm` are not separately installed via `actions/setup-node`, `pnpm/action-setup`, `corepack enable`, or other means

#### Scenario: New job needing gx

- **GIVEN** a new workflow job needs to run `gx lint` or `gx tidy`
- **WHEN** the job is authored
- **THEN** it contains exactly one `uses: jdx/mise-action@v4` step before any `gx` invocation
- **AND** `gx` is not separately installed via `jaxxstorm/action-install-gh-release` or other means

#### Scenario: New job needing container-structure-test

- **GIVEN** a new workflow job needs to run `container-structure-test test --image <ref> --config <path>` against a built image
- **WHEN** the job is authored
- **THEN** it contains exactly one `uses: jdx/mise-action@v4` step before the `container-structure-test` invocation
- **AND** `container-structure-test` is not separately installed via `plexsystems/container-structure-test-action`, `jaxxstorm/action-install-gh-release`, or hand-rolled `curl | tar`

#### Scenario: mise-action runs without explicit token configuration

- **GIVEN** the workflow grants `permissions: contents: read` (the default in this repo)
- **WHEN** `jdx/mise-action@v4` resolves `cue`, `node`, `pnpm`, or `container-structure-test` from `mise.toml`
- **THEN** the step succeeds without an explicit `github_token` input

### Requirement: Action manifest tracks the bootstrap action

`jdx/mise-action` SHALL be present in `.github/gx.toml` with a major-version constraint (`^N`), and `.github/gx.lock` SHALL pin a resolved commit SHA. The two predecessor actions — `jaxxstorm/action-install-gh-release` and `actions/setup-node` — SHALL NOT appear in `.github/gx.toml`, `.github/gx.lock`, or any workflow `uses:` reference, since no remaining workflow relies on them after this change.

**Experience context:** A maintainer auditing the project's third-party action surface from `.github/gx.toml` sees the live set: one tool-bootstrap action, not the residue of past approaches. Renovate updates target the right action.

#### Scenario: gx manifest reflects the bootstrap action

- **GIVEN** `.github/gx.toml` is read
- **WHEN** the maintainer scans the `[actions]` table
- **THEN** an entry `"jdx/mise-action" = "^4"` (or current major) is present
- **AND** no entries for `"jaxxstorm/action-install-gh-release"` or `"actions/setup-node"` remain

#### Scenario: Workflow uses match the manifest

- **GIVEN** every workflow under `.github/workflows/`
- **WHEN** `uses:` references are extracted
- **THEN** the only tool-bootstrap action referenced is `jdx/mise-action@<pinned-sha>`
- **AND** the pinned SHA in each `uses:` line matches the resolved SHA recorded in `.github/gx.lock` under `[actions."jdx/mise-action"."<major>"]`

### Requirement: `docs/src` build uses pnpm as its package manager

The `docs/src` MDX→Markdown build SHALL invoke `pnpm` (not `npm`, `yarn`, or `bun`) for dependency installation and script execution, in every CI workflow that builds the docs and in the local-developer contract. `docs/src/package.json` SHALL declare this contract via the `devEngines.packageManager` block with `name: "pnpm"` and `onFail: "error"`, and the lockfile committed at `docs/src/pnpm-lock.yaml` SHALL be the only lockfile under `docs/src/` (no `package-lock.json`, no `yarn.lock`, no `bun.lockb`).

**Experience context:** A contributor cloning the repo and running the docs build locally gets a single, predictable command path (`pnpm install && pnpm run build` from `docs/src/`) and a hard error if they reach for `npm install` out of habit. A CI engineer reading `mise.toml` and any of the three docs-building workflows sees the same package manager invoked consistently — no per-workflow drift between `npm`, `corepack`-shimmed pnpm, and action-installed pnpm.

#### Scenario: Contributor runs the wrong package manager locally

- **GIVEN** a contributor has cloned the repo and `cd`'d into `docs/src/`
- **WHEN** they run `npm install`
- **THEN** the command exits non-zero with a `devEngines` mismatch error indicating that this project requires `pnpm`
- **AND** no `node_modules` or `package-lock.json` is created

#### Scenario: CI workflow builds the docs

- **GIVEN** any of `build.yml`, `update_docs.yml`, or `update_version.yml` runs the docs-build step
- **WHEN** the build job executes
- **THEN** the step body is exactly `pnpm install --frozen-lockfile` followed by `pnpm run build`, preceded by a `jdx/mise-action@<pinned>` bootstrap step
- **AND** the step does not invoke `npm`, `corepack`, or `pnpm/action-setup` anywhere

#### Scenario: Only one lockfile lives under `docs/src/`

- **GIVEN** a contributor inspects `docs/src/`
- **WHEN** they list the directory
- **THEN** `pnpm-lock.yaml` is present
- **AND** no `package-lock.json`, `yarn.lock`, or `bun.lockb` file is present

