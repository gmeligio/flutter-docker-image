# ci-workflow-hardening Specification

## Purpose

Define the baseline security posture every workflow under `.github/workflows/` SHALL meet — least-privilege token scopes, serialized release runs, SHA-pinned third-party actions, runtime egress observability via harden-runner, and rejection of the `pull_request_target` "pwn request" pattern. The experience context is the maintainer reviewing a workflow PR or responding to a Scorecard/Dependabot signal: every guardrail here is something they would otherwise have to catch by hand, and that they can verify with a single grep or a single tab of the run summary.

## Requirements

### Requirement: Every workflow declares a minimum-scope `permissions:` block

Every YAML file under `.github/workflows/` SHALL declare a top-level `permissions:` block. The default scope SHALL be `contents: read`; any broader scope SHALL be declared at job level (not workflow level) on the specific job that needs it, with a comment naming why.

The experience context is the maintainer reviewing a PR that touches workflows — a single grep (`grep -L "^permissions:" .github/workflows/*.yml`) returns nothing, and Scorecard's `TokenPermissionsID` check reports score 10 for the permissions dimension.

#### Scenario: Workflow with no privileged operations declares read-only scope

- **GIVEN** a workflow that only reads code (lint, validate, scan)
- **WHEN** the workflow is reviewed
- **THEN** the top-level `permissions:` block contains only `contents: read`
- **AND** no job overrides this

#### Scenario: Workflow that pushes commits declares write at the job level

- **GIVEN** a workflow that pushes commits, tags, or images
- **WHEN** the workflow is reviewed
- **THEN** the top-level `permissions:` block is `contents: read`
- **AND** the specific job that pushes declares its required write scope (e.g. `contents: write`, `packages: write`) at job level with a comment

#### Scenario: A new workflow added without a `permissions:` block fails review

- **GIVEN** a PR adds a new file under `.github/workflows/`
- **WHEN** the file has no top-level `permissions:` block
- **THEN** the PR is blocked at review (and Scorecard will report `TokenPermissionsID` on the next scan)

### Requirement: Push-triggered workflows that mutate shared state declare concurrency

Every workflow triggered by `push:` or `schedule:` that mutates shared state (commits, tags, image registries, deployed artifacts) SHALL declare a top-level `concurrency:` block grouped on `${{ github.workflow }}-${{ github.ref }}`. Release-path workflows (those that push commits, tags, or images) SHALL set `cancel-in-progress: false` to serialize. CI workflows (those that only validate) MAY set `cancel-in-progress: true` to discard superseded runs.

The experience context is the maintainer who merges two PRs within a minute — without concurrency control, two release workflows race for the same tag and the second silently fails or, worse, overwrites the first. With it, the second queues and runs cleanly after the first.

#### Scenario: Two pushes to `main` arrive within seconds of each other

- **GIVEN** two PRs merge to `main` 5 seconds apart, both touching files that trigger `update-version.yml`
- **WHEN** the workflow runs
- **THEN** the second run queues (does not start) until the first completes
- **AND** neither run fails on a tag-already-exists or commit-conflict error

#### Scenario: `ci.yml` receives a follow-up push while a run is in progress

- **GIVEN** `ci.yml` is running for commit A and a new commit B is pushed
- **WHEN** the workflow detects the in-progress run
- **THEN** the run for A is cancelled and a new run starts for B
- **AND** only the latest commit's status appears on the branch

### Requirement: Third-party actions are SHA-pinned and version-consistent across workflows

Every third-party action `uses:` SHALL be pinned to a 40-character commit SHA with a trailing `# v<semver>` comment. Where the same action is used in multiple workflows in this repo, all usages SHALL pin to the same SHA.

The experience context is the maintainer reviewing a Dependabot bump — a single SHA appears in the diff per action, not several, and the bump applies cleanly to every usage at once. Drift signals an incomplete prior update and risks one workflow running unreviewed older code.

#### Scenario: An action used in N workflows is bumped

- **GIVEN** `docker/metadata-action` is used in 4 workflows
- **WHEN** Dependabot opens a PR to bump it
- **THEN** the PR diff updates 4 lines to the same new SHA
- **AND** no workflow is left on the old SHA

#### Scenario: A new workflow adds an action used elsewhere

- **GIVEN** a contributor adds a workflow using `docker/login-action`
- **WHEN** they pin it
- **THEN** they pin to the same SHA already in use in this repo
- **AND** they do not introduce a second SHA for the same action

### Requirement: Every job starts with harden-runner

Every job in every workflow SHALL declare `step-security/harden-runner` as its first step. The initial policy SHALL be `egress-policy: audit` to record outbound network calls without blocking. Promotion to `egress-policy: block` MAY happen per-job in a follow-up change once an egress baseline is established.

The experience context is the maintainer who needs to detect a compromised action that silently exfiltrates a secret — without harden-runner the egress is invisible; with it, the job summary lists every domain contacted and the maintainer can compare against the expected baseline.

#### Scenario: A job runs and harden-runner audit-mode log is present

- **GIVEN** a job that builds and pushes an image
- **WHEN** the job completes
- **THEN** the harden-runner summary lists every outbound domain (registries, package mirrors, action endpoints)
- **AND** no domain is blocked (audit mode)
- **AND** the summary is available in the run's "Security insights" tab

#### Scenario: A new job is added without harden-runner

- **GIVEN** a PR adds a new job
- **WHEN** the job has no harden-runner step
- **THEN** the PR is blocked at review

### Requirement: PR-triggered workflows use `pull_request`, not `pull_request_target`

No workflow under `.github/workflows/` SHALL use `pull_request_target` without a security review noted in the change proposal that introduces it. Privileged workflows (those with access to secrets or write-scoped `GITHUB_TOKEN`) SHALL NOT `actions/checkout` of `${{ github.event.pull_request.head.sha }}` or any fork-controlled ref. The safe default is `on: pull_request:`, which runs in the fork's context without secrets.

The experience context is the maintainer reviewing a contributor PR — secrets are not exposed to the PR's code, and a malicious PR cannot execute trusted post-processing on its own contents. This requirement defends against the "pwn request" attack class documented by JFrog, Wiz, and StepSecurity, and exploited in the May 2026 TanStack npm supply-chain compromise.

#### Scenario: A PR from a fork triggers `build.yml`

- **GIVEN** a contributor opens a PR from a fork
- **WHEN** `build.yml` runs
- **THEN** the workflow runs in the fork's context with no access to repo secrets
- **AND** the Docker Hub login step is gated by `if: github.event.pull_request.head.repo.full_name == github.repository` and is skipped for the fork
- **AND** the image is built but pushed only to a fork-scoped artifact, not to GHCR

#### Scenario: A PR proposes adding `pull_request_target` to a workflow

- **GIVEN** a PR adds `on: pull_request_target:` to any workflow
- **WHEN** the PR is reviewed
- **THEN** the change proposal under `openspec/changes/` documents the threat model and explicitly mitigates the pwn-request pattern (e.g. no checkout of PR HEAD, or split into untrusted-build + trusted-postprocess)
- **AND** without that documentation the PR is rejected

#### Scenario: A privileged workflow attempts to check out PR HEAD

- **GIVEN** any workflow that has access to secrets or write-scoped `GITHUB_TOKEN`
- **WHEN** it contains `ref: ${{ github.event.pull_request.head.sha }}` or `${{ github.head_ref }}`
- **THEN** the PR is blocked at review
- **AND** the alternative pattern (`pull_request` trigger, or a two-workflow split using `workflow_run`) is required

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
