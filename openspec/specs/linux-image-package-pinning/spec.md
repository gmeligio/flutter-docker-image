# linux-image-package-pinning Specification

## Purpose

Keeps the Linux (`android.Dockerfile`) image's self-pinned package versions current and trustworthy by making them visible to Renovate. Covers how the `deb` custom manager in `.github/renovate.json` matches the Dockerfile, the `ARG`-only declaration convention that determines what Renovate can see, and the invariant that every `# renovate:` annotation names the dependency actually installed with the correct datasource. The desktop user this serves is the CI engineer or maintainer who needs confidence that the image's apt-package version pins receive automated upgrade PRs rather than silently going stale.

## Requirements

### Requirement: Debian apt-package pins in `android.Dockerfile` are matched by Renovate's deb custom manager

The `deb`-datasource custom manager in `.github/renovate.json` SHALL match `android.Dockerfile` so that every `# renovate:`-annotated apt-package version pin receives automated upgrade PRs. The manager's `managerFilePatterns` SHALL be a pattern that matches `*.Dockerfile` files regardless of their basename prefix (e.g. the glob `**/*.Dockerfile`), not an anchored regex bound to a single literal filename.

**Experience context:** A CI engineer or maintainer asking *"are the image's apt package versions kept current automatically?"* relies on Renovate opening weekly PRs for curl, git, lcov, ca-certificates, unzip, ruby-full, build-essential, openjdk-17-jdk-headless, and sudo. Before this requirement, the manager's pattern (`/^Dockerfile$/`) matched no file after the `Dockerfile → android.Dockerfile` rename, so every pin silently went stale with no signal. Binding the pattern to the `*.Dockerfile` suffix rather than a literal name means a future rename or a new `*.Dockerfile` does not silently re-break automated pinning.

#### Scenario: Custom manager matches the renamed Dockerfile

- **GIVEN** the deb custom manager in `.github/renovate.json`
- **WHEN** Renovate evaluates the repository
- **THEN** its `managerFilePatterns` matches `android.Dockerfile`
- **AND** each `# renovate: suite=… depName=…` pin in that file is extracted as a `deb` dependency

#### Scenario: Pattern survives a Dockerfile rename or addition

- **GIVEN** a maintainer renames `android.Dockerfile` or adds a new `*.Dockerfile` carrying `# renovate:` apt pins
- **WHEN** Renovate evaluates the repository
- **THEN** the custom manager matches the file without any edit to `.github/renovate.json`

#### Scenario: A stale pin would have been caught

- **GIVEN** the custom manager matches `android.Dockerfile`
- **WHEN** an apt package pinned in that file has a newer version in the configured Debian suite
- **THEN** Renovate opens an upgrade PR for that pin on its weekly schedule

### Requirement: Self-pinned image version values are declared with `ARG`, never `ENV`

Every Renovate-managed `*_VERSION` value in `android.Dockerfile` — a value carrying a `# renovate:` annotation and a literal default — SHALL be declared with `ARG`, not `ENV`. The `matchStrings` regex SHALL remain `ARG`-only, so the convention is enforced by what Renovate can match: an `ENV`-declared pin is invisible to the manager and therefore a defect.

**Experience context:** A maintainer reading `android.Dockerfile` sees one keyword convention for self-pinned versions, with no `ENV` exceptions to explain. Build-only version strings do not leak into the final image's runtime environment or `docker inspect` metadata, and cannot collide with a real runtime variable a tool might read from the environment. The uppercase/lowercase `ARG` distinction is preserved and orthogonal: UPPERCASE-with-default names are self-pinned and Renovate-managed; lowercase names without a default are injected at build time via `--build-arg` from CI and are intentionally outside Renovate's scope.

#### Scenario: A managed version pin uses ARG

- **GIVEN** any `# renovate:`-annotated `*_VERSION` value in `android.Dockerfile`
- **WHEN** a maintainer reads its declaration
- **THEN** it is declared with `ARG`
- **AND** no `# renovate:`-annotated `*_VERSION` value is declared with `ENV`

#### Scenario: Build-only version does not persist into the image

- **GIVEN** the built Linux image
- **WHEN** a maintainer runs `docker inspect` on it
- **THEN** no `*_VERSION` apt-package pin appears in the image's `Env` configuration

#### Scenario: Externally injected build args keep the lowercase convention

- **GIVEN** a build argument supplied at build time via `--build-arg` (e.g. `flutter_version`, `fastlane_version`)
- **WHEN** a maintainer reads its declaration
- **THEN** it is a lowercase `ARG` with no default value and no `# renovate:` annotation
- **AND** Renovate does not attempt to manage it

### Requirement: Each `# renovate:` annotation names the dependency actually installed, with the correct datasource

Every `# renovate:` annotation in `android.Dockerfile` SHALL name, in its `depName`, the exact dependency that the corresponding `RUN` line installs, and SHALL use the datasource matching that dependency's ecosystem. A `deb`-ecosystem pin SHALL use the `suite=` form (deb datasource). A version value managed elsewhere (e.g. via the `config/version.json` manifest and a `--build-arg`) SHALL NOT carry a contradicting inline `# renovate:` annotation.

**Experience context:** A maintainer reading a pin trusts that Renovate is tracking *that* package. A wrong `depName` is worse than an unmatched pin: Renovate feeds the wrong dependency's version into the `ARG`, which can break the build (e.g. a `ruby-dev` version string applied to a `ruby-full` install) or silently track an unrelated project. One such defect existed — `RUBY_VERSION` annotated `depName=ruby-dev` while the `RUN` installs `ruby-full`. The `fastlane` gem is intentionally not pinned here at all: its version is owned by `config/version.json` and fanned out to the build (`--build-arg fastlane_version`) and the rendered docs, so an inline `depName=fastlane` would be both wrong and redundant.

#### Scenario: deb pin names the installed package

- **GIVEN** the `RUBY_VERSION` pin, whose `RUN` line installs `ruby-full`
- **WHEN** a maintainer reads its `# renovate:` annotation
- **THEN** the `depName` is `ruby-full`, not `ruby-dev`

#### Scenario: Manifest-managed gem is not double-pinned inline

- **GIVEN** the `fastlane` gem, whose version is owned by `config/version.json` and injected via `--build-arg fastlane_version`
- **WHEN** a maintainer scans `android.Dockerfile` for `# renovate:` annotations
- **THEN** no annotation names `fastlane` as a `depName`
- **AND** Renovate does not surface `fastlane` as a managed dependency of the Dockerfile
