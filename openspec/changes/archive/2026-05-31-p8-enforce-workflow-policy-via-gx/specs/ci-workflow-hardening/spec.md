## ADDED Requirements

### Requirement: Structural properties are enforced by `gx lint` in CI

The structural properties this specification mandates — top-level `permissions:` block, `concurrency:` on push/schedule triggers, SHA-pinned third-party actions, rejection of unreviewed `pull_request_target`, and fork-secret gates on PR-triggered workflows — SHALL be enforced mechanically by `gx lint` running on every pull request. Maintainer review SHALL NOT be the primary enforcement mechanism for these properties.

The enforcing rules SHALL be configured at error-level severity in `.github/gx.toml` so a violation fails the PR check rather than emitting a soft warning. The mapping from spec requirement to enforcing gx rule SHALL be recorded as comments in `.github/gx.toml` alongside the rule configuration, and SHALL be kept current when either side changes. (No SECURITY.md file is used for this mapping.)

Where a rule produces a finding that is a true pattern match but not exploitable given an existing fork gate, the workflow SHALL be exempted with a narrowly-scoped `ignore` entry in `.github/gx.toml` that names the workflow and carries a comment explaining why the finding is safe. An `ignore` SHALL NOT disable a rule globally where a scoped exemption suffices.

The experience context is the maintainer reviewing a contributor PR or their own work — they trust that "`gx lint` passed" means the structural properties hold, and they spend review attention on intent and design rather than re-checking the checklist by hand.

#### Scenario: A PR introduces a workflow without a `permissions:` block

- **GIVEN** a PR adds a new file under `.github/workflows/` with no top-level `permissions:` block
- **WHEN** CI runs
- **THEN** the `gx lint` job fails with a `missing-permissions` error diagnostic
- **AND** the maintainer does not need to catch the omission in review

#### Scenario: A PR introduces a fork-unsafe secret reference

- **GIVEN** a PR modifies a `pull_request`-triggered workflow to reference `secrets.DOCKER_HUB_TOKEN` in a step
- **WHEN** the step lacks an `if: github.event.pull_request.head.repo.full_name == github.repository` guard
- **THEN** the `gx lint` job fails with an `unprotected-secrets` error diagnostic

#### Scenario: A PR proposes `pull_request_target`

- **GIVEN** a PR adds `on: pull_request_target:` to any workflow
- **WHEN** CI runs
- **THEN** the `gx lint` job fails with a `dangerous-trigger` error diagnostic
- **AND** the contributor is directed to document the threat model in a change proposal (per the existing scenario in this spec)
- **AND** the workflow file SHALL gain a scoped `dangerous-trigger` ignore entry in `.github/gx.toml`, with a comment naming the reviewed threat model, before the PR can land

#### Scenario: A reviewed privileged workflow trips a pattern-match rule

- **GIVEN** a workflow whose privileged job checks out the PR HEAD ref but is already fork-gated (e.g. `.github/workflows/gx.yml`'s `tidy` job)
- **WHEN** `gx lint` runs
- **THEN** the `pr-head-checkout` rule emits a diagnostic for the pattern
- **AND** the workflow SHALL carry a scoped `ignore` entry naming it, with a comment explaining the fork gate makes the pattern non-exploitable
- **AND** `gx lint` exits 0 with that exemption in place

#### Scenario: The gx version pinned in the repo lacks the enforcing rule

- **GIVEN** a Dependabot or Renovate PR downgrades the gx version below the release that ships these rules
- **WHEN** CI runs
- **THEN** the maintainer recognizes the regression and rejects the PR
- **AND** the gx version pin SHALL only be raised, not lowered, once this requirement is in effect

#### Scenario: A new structural property is added to this spec

- **GIVEN** a future change proposes a new structural requirement (e.g., "every workflow declares `timeout-minutes` at job level")
- **WHEN** the proposal is reviewed
- **THEN** the proposal SHALL identify the gx rule that enforces the new requirement, or SHALL declare that a gx rule will be added (with a tracked dependency)
- **AND** a structural requirement without a mechanical enforcement path is rejected — the spec stays load-bearing only because every requirement has a gate
