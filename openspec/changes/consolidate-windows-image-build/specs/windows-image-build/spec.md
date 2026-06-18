## ADDED Requirements

### Requirement: A single reusable workflow builds the Windows image for every path

`.github/workflows/windows-image.yml` SHALL be a `workflow_call` reusable workflow that is the only place `windows.Dockerfile` is built. It SHALL accept inputs `target` (string, passed to `docker build --target`), `push` (boolean), and `can-login` (boolean), accept registry credentials via `secrets: inherit`, and SHALL build `windows.Dockerfile` on `windows-2025` with exactly the five build-args `flutter_version`, `git_version`, `vs_cmake_version`, `vs_win11sdk_build`, and `vs_vctools_version` read from `config/version.json` via `script/setEnvironmentVariables.js`. Both the PR-test path (`windows.yml`) and the release path (`release.yml`) SHALL invoke this workflow as a `uses:` caller job rather than building `windows.Dockerfile` with their own inline steps.

The experience context is the maintainer editing the Windows build — a new VS component, a build-arg, a runner bump, or a registry change is made in one file and takes effect identically on both the PR check and the release publish; the two paths cannot drift because there is only one build definition.

#### Scenario: Both paths resolve to the same build definition

- **GIVEN** `windows.yml` and `release.yml`
- **WHEN** their Windows jobs are inspected
- **THEN** each is a `uses: ./.github/workflows/windows-image.yml` caller job
- **AND** neither contains an inline `docker build ... windows.Dockerfile` step
- **AND** the five build-args are supplied only inside `windows-image.yml`

#### Scenario: Target is selected by the caller

- **GIVEN** a caller passing `target: test`
- **WHEN** the reusable workflow runs
- **THEN** it builds `docker build ... --target test`
- **AND** a caller passing `target: flutter` builds `--target flutter` from the same workflow

### Requirement: The runner disk is cleaned and asserted before the Windows build

The reusable workflow SHALL run `./.github/actions/clean-runner-disk` before `docker build`, on every invocation regardless of `target` or `push`. Because `clean-runner-disk` asserts ≥ 40 GB free on `C:` and fails the step otherwise, a `windows-2025` runner with insufficient free space SHALL fail at the cleanup step with a named free-space message rather than mid-build inside the VS Build Tools install.

The experience context is the CI engineer cutting a release: the release path previously skipped cleanup and the build died installing VS Build Tools with `There is not enough space on the disk` on the ~33 GB default runner. Routing both paths through the shared cleanup makes that failure impossible to reach silently.

#### Scenario: Release build no longer OOMs on VS Build Tools

- **GIVEN** a tag push that builds the Windows image with `target: flutter`, `push: true`
- **WHEN** the reusable workflow runs
- **THEN** `clean-runner-disk` runs before `docker build`
- **AND** the VS Build Tools install step completes without a `not enough space on the disk` error

#### Scenario: Insufficient space fails at cleanup, not mid-build

- **GIVEN** a runner-image change that leaves < 40 GB free on `C:` after cleanup
- **WHEN** the reusable workflow runs
- **THEN** the `clean-runner-disk` assertion fails the job with the actual free space named
- **AND** `docker build` does not run

### Requirement: The Docker daemon is confirmed ready before the build

The reusable workflow SHALL ensure the Windows Docker daemon is running and answering before invoking `docker build`, starting the `docker` service and polling `docker version` until it responds (workaround for actions/runner-images#13729, where the daemon does not always auto-start on `windows-2025`).

The experience context is the maintainer whose release or PR run would otherwise fail intermittently at `docker build` with a daemon-not-running error on an unlucky runner; the guard makes the build deterministic on both paths.

#### Scenario: Daemon is started when not running

- **GIVEN** a `windows-2025` runner whose `docker` service is not in the `Running` state
- **WHEN** the reusable workflow runs
- **THEN** it starts the service and waits until `docker version` succeeds before `docker build`
- **AND** the build proceeds against a ready daemon

### Requirement: Registry logins are fork-safe and gated by intent

The reusable workflow SHALL log in to Docker Hub only when `can-login` is true, and SHALL log in to GitHub Container Registry and Quay.io only when `push` is true. A caller with `can-login: false` (a pull request from a fork, where secrets are unavailable) SHALL build and run the Windows image without attempting any registry login.

The experience context is the external contributor opening a PR from a fork — the Windows check builds and runs the Pester suite without failing on a missing-secret login, while the release path still authenticates to all three registries before pushing.

#### Scenario: Fork PR builds and tests without logging in

- **GIVEN** a caller passing `can-login: false`, `push: false`
- **WHEN** the reusable workflow runs
- **THEN** no Docker Hub, GHCR, or Quay login step executes
- **AND** the image builds `--target test` and the Pester suite runs

#### Scenario: Release path authenticates to all three registries

- **GIVEN** a caller passing `can-login: true`, `push: true`
- **WHEN** the reusable workflow runs
- **THEN** it logs in to Docker Hub, GHCR, and Quay.io before pushing
- **AND** the built tags are pushed to all three

### Requirement: The build job starts with harden-runner

The job inside `windows-image.yml` SHALL declare `step-security/harden-runner` with `egress-policy: audit` as its first step, so that the Windows build's outbound egress is recorded on both the PR-test and release invocations. The `uses:` caller jobs in `windows.yml` and `release.yml` run no steps of their own and therefore carry harden-runner via this called workflow's job.

The experience context is the maintainer auditing supply-chain egress: the Windows build path — previously the only build with no harden-runner coverage — now appears in the run's Security insights alongside the Android build.

#### Scenario: Windows build records egress in audit mode

- **GIVEN** any invocation of `windows-image.yml` (test or release)
- **WHEN** the job runs
- **THEN** harden-runner is its first step with `egress-policy: audit`
- **AND** the run's harden-runner summary lists the outbound domains contacted during the build
- **AND** no domain is blocked (audit mode)
