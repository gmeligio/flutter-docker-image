## ADDED Requirements

### Requirement: Debian apt-package pins in `android.Dockerfile` are matched by Renovate's deb custom manager

The `deb`-datasource custom manager in `.github/renovate.json` SHALL match `android.Dockerfile` so that every `# renovate:`-annotated apt-package version pin receives automated upgrade PRs. The manager's `managerFilePatterns` SHALL be a pattern that matches `*.Dockerfile` files regardless of their basename prefix (e.g. the glob `**/*.Dockerfile`), not an anchored regex bound to a single literal filename.

**Experience context:** A CI engineer or maintainer asking *"are the image's apt package versions kept current automatically?"* relies on Renovate opening weekly PRs for curl, git, lcov, ca-certificates, unzip, ruby-dev, build-essential, openjdk-17-jdk-headless, and sudo. Before this requirement, the manager's pattern (`/^Dockerfile$/`) matched no file after the `Dockerfile → android.Dockerfile` rename, so every pin silently went stale with no signal. Binding the pattern to the `*.Dockerfile` suffix rather than a literal name means a future rename or a new `*.Dockerfile` does not silently re-break automated pinning.

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

**Experience context:** A maintainer reading `android.Dockerfile` sees one keyword convention for self-pinned versions, with no `ENV` exceptions to explain. Build-only version strings do not leak into the final image's runtime environment or `docker inspect` metadata, and cannot collide with a real runtime variable — `bundler` reads `BUNDLER_VERSION` from the environment, so a persisted `ENV BUNDLER_VERSION` could silently influence runtime tooling. The uppercase/lowercase `ARG` distinction is preserved and orthogonal: UPPERCASE-with-default names are self-pinned and Renovate-managed; lowercase names without a default are injected at build time via `--build-arg` from CI and are intentionally outside Renovate's scope.

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
