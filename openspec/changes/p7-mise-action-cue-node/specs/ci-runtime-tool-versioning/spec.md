## ADDED Requirements

### Requirement: Single-source version manifest for CI runtime tools

The repository SHALL pin every CI runtime tool version (currently `cue` and `node`) in `mise.toml` at the repository root. No workflow under `.github/workflows/` or composite action under `.github/actions/` may install `cue` or `node` by any other mechanism (e.g., `jaxxstorm/action-install-gh-release`, `actions/setup-node`, hand-rolled `curl | tar`).

**Experience context:** A CI engineer or maintainer asking *"what version of cue does CI run with?"* (or `node`) reads exactly one file — `mise.toml` — and gets a single, authoritative answer. Today the answer is duplicated across 9 CUE-install steps and 3 Node-install steps, which has produced version drift and made point-fixes fragile.

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

#### Scenario: Drift attempt is blocked at review

- **GIVEN** a PR adds a step `uses: actions/setup-node@<sha>` to any workflow
- **WHEN** the PR is reviewed
- **THEN** the change is rejected and re-implemented using `jdx/mise-action@v4` plus the appropriate `mise.toml` pin
- **AND** the rationale references this requirement

### Requirement: Workflows bootstrap tools via `jdx/mise-action`

Every job that needs `cue` or `node` on `$PATH` SHALL bootstrap them with a single step `uses: jdx/mise-action@<pinned-major>` placed before any step that invokes those tools. The step SHALL rely on `mise.toml` for version resolution and SHALL NOT pass an explicit `tools:` input that contradicts `mise.toml`.

**Experience context:** A maintainer adding a new CI job that needs `cue` or `node` writes one boilerplate step (the same step every other job uses) and gets the project-pinned version. They never re-derive a download URL or copy a SHA digest.

#### Scenario: New job needing CUE

- **GIVEN** a new workflow job needs to run `cue vet`
- **WHEN** the job is authored
- **THEN** it contains exactly one tool-bootstrap step `uses: jdx/mise-action@v4` before the `cue` invocation
- **AND** no `with:` input overrides `cue`'s version

#### Scenario: New job needing Node

- **GIVEN** a new workflow job needs to run `npm ci && npm run build`
- **WHEN** the job is authored
- **THEN** it contains exactly one `uses: jdx/mise-action@v4` step before any `npm` invocation
- **AND** `node` is not separately installed via `actions/setup-node` or other means

#### Scenario: mise-action runs without explicit token configuration

- **GIVEN** the workflow grants `permissions: contents: read` (the default in this repo)
- **WHEN** `jdx/mise-action@v4` resolves `cue` and `node` from `mise.toml`
- **THEN** the step succeeds without an explicit `github_token` input
- **AND** the GitHub API calls used to resolve releases are authenticated by the action's default `${{ github.token }}`

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
