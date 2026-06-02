## ADDED Requirements

### Requirement: All writes to the default branch go through a pull request

No workflow SHALL push commits directly to `~DEFAULT_BRANCH`. Every change that lands on the default branch — including automated changelog updates and regenerated documentation — SHALL arrive via a pull request that is subject to the branch ruleset (required status checks, signatures, linear history, CODEOWNERS review).

The experience context is the maintainer trusting that the protected branch's history reflects only reviewed-or-gated changes: there is no side channel by which a workflow mutates `main` without passing the same checks a human PR passes.

#### Scenario: A version bump carries its changelog

- **GIVEN** `update-version.yml` detects a newer Flutter version
- **WHEN** it opens the version-bump pull request
- **THEN** the regenerated `changelog.md` for the new version is part of that same PR
- **AND** the version change and its changelog reach `main` together, only after the PR's required checks pass and it is merged
- **AND** no commit is pushed directly to `main`

#### Scenario: A release is tagged from the merged version

- **GIVEN** a version-bump PR merges, changing `config/version.json` on `main`
- **WHEN** `prepare-release.yml` runs
- **THEN** it creates the version tag from the merged commit without pushing any commit
- **AND** the tag push triggers `release.yml`

#### Scenario: Documentation source is edited in a PR

- **GIVEN** a pull request changes a `docs/src/**` source file
- **WHEN** `update-docs.yml` runs on that pull request
- **THEN** it regenerates the committed docs output and commits it onto the same PR branch
- **AND** the regenerated output is reviewed in the same PR that edited the source
- **AND** no commit is pushed directly to `main`

#### Scenario: Documentation output is already in sync

- **GIVEN** a pull request whose `docs/src/**` change produces no output diff
- **WHEN** `update-docs.yml` runs
- **THEN** it pushes nothing and does not re-trigger itself
- **AND** the PR is unchanged

### Requirement: The default-branch ruleset has no bypass actor

The active ruleset for `~DEFAULT_BRANCH` SHALL NOT define any `bypass_actors`. Because every write now flows through a PR, no App or actor needs to bypass the rules. The ruleset is managed as code outside this repository; this requirement is the in-repo contract that the workflows here do not depend on a bypass existing.

The experience context is the auditor (or Scorecard's `EnforceAdmins` check) confirming the protected branch has no unexplained loophole — the bypass list is empty, and no workflow regresses by reintroducing a direct push that would require one.

#### Scenario: A workflow attempts a direct push to main

- **GIVEN** the ruleset has no bypass actor
- **WHEN** any workflow attempts to push a commit directly to `main`
- **THEN** the push is rejected by the ruleset
- **AND** the only way to land the change is through a pull request

#### Scenario: Tag creation is unaffected by bypass removal

- **GIVEN** the ruleset targets `~DEFAULT_BRANCH` (branches), not tags
- **WHEN** `prepare-release.yml` creates a version tag via the GitHub API (`refs/tags/*`)
- **THEN** the tag is created successfully without any bypass actor
- **AND** the tag push still triggers `release.yml`

### Requirement: Trusted automated pull requests auto-merge on passing checks

Pull requests from trusted automation (Renovate; the release/docs App) SHALL merge automatically once all required status checks pass, without a manual merge action. This relies on GitHub-native auto-merge, not on any approval step — approvals are not required to merge (`required_approving_review_count` is `0`), so no auto-approval workflow exists. At least one required status check SHALL be configured so auto-merge cannot merge a failing PR.

The experience context is the maintainer who wants lockfile bumps and routine release/docs PRs to merge promptly on green, while every PR still passes the full required-check gate and falls back to manual attention if a check fails.

#### Scenario: A Renovate PR passes all checks

- **GIVEN** Renovate opens a PR and `automerge`/`platformAutomerge` are enabled
- **WHEN** all required status checks pass
- **THEN** GitHub merges the PR automatically
- **AND** no manual merge click and no approval are required

#### Scenario: A Renovate PR fails a check

- **GIVEN** a Renovate PR with auto-merge enabled
- **WHEN** any required status check fails
- **THEN** GitHub does NOT merge the PR
- **AND** the PR stays open for the maintainer's attention

#### Scenario: No required status check is configured

- **GIVEN** auto-merge is enabled on PRs
- **WHEN** the required-status-checks configuration is reviewed
- **THEN** at least one required check is present
- **AND** auto-merge therefore cannot merge a PR with failing or absent checks
