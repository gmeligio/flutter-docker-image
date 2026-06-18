## ADDED Requirements

### Requirement: Pull request CI builds and validates the `flutter-web` image on every PR

The `.github/workflows/build.yml` workflow SHALL build the `flutter-web` image (`android.Dockerfile` with `--target web`) on every `pull_request` event, and SHALL run `container-structure-test` against it using `test/web.yml`. The web image SHALL be added as a matrix dimension over `{IMAGE_REPOSITORY_NAME, target}` alongside the android image, not as a copied set of jobs, so that the build, handoff, cache, test, and scan steps remain single definitions shared by both images.

The experience context is the maintainer reviewing a PR that touches `android.Dockerfile` or `test/web.yml` — they get a single red/green web check, produced by the same job logic that validates the android image, rather than a divergent copy that can rot independently.

#### Scenario: Web check is green when the image is healthy

- **GIVEN** a PR whose `android.Dockerfile` `web` stage builds successfully
- **AND** every test in `test/web.yml` passes inside the resulting `web`-target image
- **WHEN** the web matrix leg of the build/test jobs runs
- **THEN** the jobs exit 0
- **AND** the web check on the PR is reported as success

#### Scenario: Web check is red when a structure test fails

- **GIVEN** a PR whose `web`-target image builds successfully
- **AND** at least one `test/web.yml` assertion fails (e.g., `flutter build web` emits a `Downloading` line)
- **WHEN** `container-structure-test` runs
- **THEN** it exits non-zero
- **AND** the web test job is reported as failed on the PR

### Requirement: `test/web.yml` asserts a no-runtime-download web build

`test/web.yml` SHALL include a `container-structure-test` command test that runs `flutter create` followed by `flutter build web`, and SHALL assert via `excludedOutput` that the output contains no `Downloading` and no `Installing` lines, mirroring the pattern in `test/android.yml`.

The experience context is the maintainer who needs the "everything is predownloaded" guarantee to be machine-checked on every PR, not just asserted in the readme — a regression that reintroduces a runtime download SHALL turn the PR check red.

#### Scenario: Structure test fails if the web build downloads at runtime

- **GIVEN** a `web`-target image built from a PR where `flutter precache --web` was removed
- **WHEN** the `flutter build web` command test in `test/web.yml` runs
- **THEN** the build emits `Downloading` lines for the web engine
- **AND** the `excludedOutput` assertion fails the test

### Requirement: Web image consumer jobs do not rebuild the image

The web image's `container-structure-test` and Docker Scout jobs SHALL consume the image via the same handoff produced by the build job (per the `ci-image-handoff` capability) — `pull` on the registry path, `download-artifact` + `docker load` on the fork-PR path. They SHALL NOT invoke `docker build` or `docker/build-push-action`.

The experience context is the maintainer auditing CI cost — each Dockerfile-touch PR SHALL materialize the web image bits exactly once, consistent with how the android image is validated.

#### Scenario: Web consumer pulls the registry image without rebuilding

- **GIVEN** a non-fork PR run
- **WHEN** the web test or scan job runs
- **THEN** the job log shows a pull of `ghcr.io/<owner>/flutter-web:pr-<N>`
- **AND** the job log does not contain `docker build` or `FROM debian:`

#### Scenario: Fork PR web scan is skipped, web test still runs

- **GIVEN** a `pull_request` event from a fork (`head.repo.full_name != github.repository`)
- **WHEN** the workflow runs
- **THEN** the web build and web test legs run against the locally-loaded artifact
- **AND** the web Scout scan leg does not appear (job-level `if:` evaluates to false), preserving the existing fork-PR scan gate
