## MODIFIED Requirements

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
