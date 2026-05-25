## ADDED Requirements

### Requirement: All workflow setup uses the `setup-build-context` composite

Every workflow under `.github/workflows/` that needs the standard setup (repository checkout, mise toolchain install, and the env vars derived from `config/version.json`) SHALL call `uses: ./.github/actions/setup-build-context` rather than inlining the three steps. The composite SHALL be the single source of truth for `actions/checkout`, `jdx/mise-action`, and the `setEnvironmentVariables.js` invocation.

The experience context is the maintainer bumping a Dependabot PR — the bump touches one composite file, not nine workflows. Drift between workflows on `actions/checkout` or `jdx/mise-action` versions becomes impossible by construction.

#### Scenario: A workflow needs the standard setup

- **GIVEN** a workflow that needs to checkout, install mise tools, and read version env vars
- **WHEN** the workflow is reviewed
- **THEN** it calls `uses: ./.github/actions/setup-build-context` with the required inputs
- **AND** it does NOT separately call `actions/checkout`, `jdx/mise-action`, or `actions/github-script` for `setEnvironmentVariables.js`

#### Scenario: The composite is bumped to a new `actions/checkout` SHA

- **GIVEN** Dependabot bumps `actions/checkout`
- **WHEN** the PR is reviewed
- **THEN** the diff touches only `.github/actions/setup-build-context/action.yml`
- **AND** every workflow inherits the bump automatically

#### Scenario: Composite outputs are consumed instead of relying on env propagation

- **GIVEN** a caller needs `FLUTTER_VERSION` from `config/version.json`
- **WHEN** the caller references it
- **THEN** the caller reads from `steps.<id>.outputs.flutter-version`, not from `env.FLUTTER_VERSION`
- **AND** the caller assigns an `id:` to the composite step so the outputs are addressable

### Requirement: All Docker registry login uses the `docker-registry-login` composite

Every workflow that authenticates to GHCR, Docker Hub, or Quay SHALL call `uses: ./.github/actions/docker-registry-login` rather than inlining `docker/login-action` calls. The composite SHALL pin `docker/login-action` to a single SHA repo-wide.

The experience context is the maintainer reviewing a new workflow — the registry-login section is one `uses:` block with a clear contract, not a hand-copied fan-out of three `docker/login-action` calls with subtly different conditionals.

#### Scenario: A workflow needs to push to GHCR only

- **GIVEN** a CI workflow that builds an image and pushes only to GHCR
- **WHEN** the workflow is reviewed
- **THEN** it calls `uses: ./.github/actions/docker-registry-login` with `ghcr: 'true'`, `dockerhub: 'false'`, `quay: 'false'`
- **AND** no inline `docker/login-action` call appears in the workflow

#### Scenario: A workflow needs to push to multiple registries

- **GIVEN** a release workflow that pushes to GHCR, Docker Hub, and Quay
- **WHEN** the workflow is reviewed
- **THEN** it calls the composite with all three flags `'true'` and passes the credentials as inputs

### Requirement: The login composite does NOT self-gate against fork PRs; the caller does

The `docker-registry-login` composite SHALL document in its README that it cannot enforce a fork-PR gate, because composite actions cannot read `secrets.*` directly. The calling job SHALL wrap the `uses:` step in `if: github.event.pull_request.head.repo.full_name == github.repository` whenever it passes Docker Hub or Quay credentials sourced from `secrets`.

The experience context is the maintainer who must defend the "secrets never reach fork PR code" invariant codified in `ci-workflow-hardening`. Centralizing the gate in the composite would silently break for any workflow whose secret source isn't visible to the composite — the safe rule is "gate at the caller, with the secret reference".

#### Scenario: A workflow runs on a fork PR

- **GIVEN** `build.yml` runs for a PR opened from a fork
- **WHEN** the docker-login step is reached
- **THEN** the calling job's `if:` evaluates to `false` and the step is skipped
- **AND** the composite is not invoked, so no secret is referenced

#### Scenario: A workflow runs on a same-repo PR

- **GIVEN** `build.yml` runs for a PR opened from the same repo
- **WHEN** the docker-login step is reached
- **THEN** the calling job's `if:` evaluates to `true`
- **AND** the composite logs into GHCR, Docker Hub (if requested), and Quay (if requested)

#### Scenario: A new workflow adds the login composite without the caller-side gate

- **GIVEN** a PR adds a workflow that calls `docker-registry-login` with Docker Hub credentials
- **WHEN** the calling job has no `if: ...head.repo.full_name == github.repository` gate
- **THEN** the PR is blocked at review with a pointer to this requirement

## MODIFIED Requirements

### Requirement: Every job starts with harden-runner

Every job in every workflow SHALL declare `step-security/harden-runner` as its first step. **Every composite action invoked from a workflow job SHALL also begin with `step-security/harden-runner`** so that composites cannot serve as a back-door around the egress audit. The initial policy SHALL be `egress-policy: audit` to record outbound network calls without blocking.

The experience context is the maintainer who needs the harden-runner audit log to be complete — if a composite skipped harden-runner, network calls made inside it would not appear in the job's egress summary, defeating the audit.

#### Scenario: A job runs and harden-runner audit-mode log is complete

- **GIVEN** a job that calls `setup-build-context` and then `docker-registry-login`
- **WHEN** the job completes
- **THEN** the egress summary lists domains reached by the job's own steps AND by both composites
- **AND** no composite-internal network call is missing from the summary
