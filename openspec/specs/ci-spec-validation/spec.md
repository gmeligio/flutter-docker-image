# ci-spec-validation Specification

## Purpose
Keep `openspec/` specs and active changes structurally valid by running `openspec validate` locally and on every pull request that touches them.

## Requirements

### Requirement: Spec changes are validated before merge

A pull request that touches `openspec/**` SHALL run a `Validate specs` check that executes `mise run specs` (`openspec validate --all`) and fails when any spec or active change is invalid. The same command SHALL run locally.

The experience context is the maintainer reviewing a spec PR — a missing `## Purpose` or malformed delta turns the check red instead of surfacing at archive time.

#### Scenario: Invalid spec fails the check

- **GIVEN** a PR that removes `## Purpose` from a spec under `openspec/specs/`
- **WHEN** the `Validate specs` check runs
- **THEN** the check fails and its log names the invalid spec

#### Scenario: Maintainer reproduces the check locally

- **GIVEN** a local checkout with mise tools installed
- **WHEN** the maintainer runs `mise run specs`
- **THEN** it reports the same result as the `Validate specs` check
