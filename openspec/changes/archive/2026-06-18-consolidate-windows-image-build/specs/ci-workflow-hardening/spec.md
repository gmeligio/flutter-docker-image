## MODIFIED Requirements

### Requirement: Every job starts with harden-runner

Every job in every workflow SHALL declare `step-security/harden-runner` as its first step. The initial policy SHALL be `egress-policy: audit` to record outbound network calls without blocking. Promotion to `egress-policy: block` MAY happen per-job in a follow-up change once an egress baseline is established.

A reusable-workflow **caller** job — one whose body is `uses: ./.github/workflows/<file>.yml` — runs no steps of its own and therefore cannot host a harden-runner step. For such caller jobs, the requirement is satisfied by the **called** workflow's job declaring harden-runner as its first step. Every job that actually executes on a runner (including the job inside a `workflow_call` reusable workflow) SHALL still start with harden-runner; the Windows build, previously the only build path without harden-runner coverage, is brought into compliance through the `windows-image.yml` reusable workflow's job.

The experience context is the maintainer who needs to detect a compromised action that silently exfiltrates a secret — without harden-runner the egress is invisible; with it, the job summary lists every domain contacted and the maintainer can compare against the expected baseline, and a reviewer reading a thin `uses:` caller job knows the coverage lives in the called workflow rather than flagging the caller as non-compliant.

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

#### Scenario: A reusable-workflow caller job delegates harden-runner to the called workflow

- **GIVEN** a caller job whose body is `uses: ./.github/workflows/windows-image.yml`
- **WHEN** the workflow is reviewed
- **THEN** the caller job is accepted without an inline harden-runner step
- **AND** the job inside `windows-image.yml` declares `step-security/harden-runner` with `egress-policy: audit` as its first step
- **AND** the Windows build's egress appears in the run's harden-runner summary
