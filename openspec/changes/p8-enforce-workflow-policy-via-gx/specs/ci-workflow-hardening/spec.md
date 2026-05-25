## ADDED Requirements

### Requirement: Structural properties are enforced by `gx lint` in CI

The structural properties this specification mandates — top-level `permissions:` block, `concurrency:` on push/schedule triggers, SHA-pinned third-party actions, rejection of unreviewed `pull_request_target`, and fork-secret gates on PR-triggered workflows — SHALL be enforced mechanically by `gx lint` running on every pull request. Maintainer review SHALL NOT be the primary enforcement mechanism for these properties.

The mapping from spec requirement to enforcing gx rule SHALL be documented in `.github/workflows/SECURITY.md` and SHALL be kept current when either side changes. The enforcing rules SHALL be configured at error-level severity in `.github/gx.toml` so a violation fails the PR check rather than emitting a soft warning.

The experience context is the maintainer reviewing a contributor PR or their own work — they trust that "`gx lint` passed" means the structural properties hold, and they spend review attention on intent and design rather than re-checking the checklist by hand.

#### Scenario: A PR introduces a workflow without a `permissions:` block

- **GIVEN** a PR adds a new file under `.github/workflows/` with no top-level `permissions:` block
- **WHEN** CI runs
- **THEN** the `gx lint` job fails with a `missing-permissions` error diagnostic
- **AND** the PR is blocked from merging by the required status check
- **AND** the maintainer does not need to catch the omission in review

#### Scenario: A PR introduces a fork-unsafe secret reference

- **GIVEN** a PR modifies a `pull_request`-triggered workflow to reference `secrets.DOCKER_HUB_TOKEN` in a step
- **WHEN** the step lacks an `if: github.event.pull_request.head.repo.full_name == github.repository` guard
- **THEN** the `gx lint` job fails with an `unprotected-secrets` error diagnostic
- **AND** the PR is blocked

#### Scenario: A PR proposes `pull_request_target`

- **GIVEN** a PR adds `on: pull_request_target:` to any workflow
- **WHEN** CI runs
- **THEN** the `gx lint` job fails with a `dangerous-trigger` error diagnostic
- **AND** the contributor is directed to document the threat model in a change proposal (per the existing scenario in this spec)
- **AND** the workflow file SHALL include a `gx.toml` ignore entry for the reviewed `pull_request_target` workflow before the PR can land

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
