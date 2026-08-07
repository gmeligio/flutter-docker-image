## ADDED Requirements

### Requirement: Each apt pin resolves against the same set of Debian suites the image enables

Every `deb`-datasource pin SHALL be resolved against the full set of apt suites enabled in the image stage that installs it — the base suite, its `-updates` suite, and its `-security` suite — expressed as a list of `registryUrls` on a `packageRules` entry in `.github/renovate.json`. Each `registryUrls` entry SHALL mirror exactly one `Types`/`URIs`/`Suites`/`Components` stanza of the image's real apt sources, in both suite and component list. Suite selection SHALL NOT be expressed via `registryUrlTemplate`, which renders a single URL and therefore cannot address a set.

**Experience context:** A CI engineer trusts that a Renovate PR bumping an apt pin produces a version the image can actually install. apt picks the highest version across every enabled suite, so if Renovate watches fewer suites than apt, the two disagree about what "latest" is. That disagreement is what broke the image: `openjdk-17-jdk-headless` was pinned to `17.0.19+10-1~deb12u2` while apt's candidate for its strict-equality dependency `openjdk-17-jre-headless` had moved to `17.0.20+8-1~deb12u1` in `bookworm-security`, and the build failed with `E: Unable to correct problems, you have held broken packages`. Security uploads for an oldstable suite land in `-security` before they are folded into the main archive at a point release, so watching only the base suite guarantees this skew recurs. Mirroring the sources stanza-for-stanza also keeps the invariant auditable: a maintainer can read the rule beside the sources file and see they agree.

#### Scenario: A pin is resolved against base, updates and security suites

- **GIVEN** an apt pin in `android.Dockerfile` installed from a suite the image enables
- **WHEN** Renovate looks the package up
- **THEN** it queries that suite, its `-updates` suite, and its `-security` suite
- **AND** the candidate it proposes is the highest version across all of them — the version apt would install

#### Scenario: A pin installed from an added repository resolves against that repository

- **GIVEN** `openjdk-17-jdk-headless`, which the android stage installs after adding `config/debian_12_bookworm.sources`
- **WHEN** Renovate looks it up
- **THEN** it queries the bookworm suites named in that sources file, not the base image's trixie suites
- **AND** a security-only update published to `bookworm-security` is offered as an upgrade PR

#### Scenario: Suites are named by codename, not by a moving alias

- **GIVEN** the deb `packageRules` in `.github/renovate.json`
- **WHEN** a maintainer reads the configured suites
- **THEN** each names a Debian codename (e.g. `trixie`, `bookworm-security`)
- **AND** none uses a floating alias such as `stable` or `oldstable`, which would silently retarget every pin when Debian promotes a new release

## MODIFIED Requirements

### Requirement: Debian apt-package pins in `android.Dockerfile` are matched by Renovate's deb custom manager

The `deb`-datasource custom manager in `.github/renovate.json` SHALL match `android.Dockerfile` so that every `# renovate:`-annotated apt-package version pin receives automated upgrade PRs. The manager's `managerFilePatterns` SHALL be a pattern that matches `*.Dockerfile` files regardless of their basename prefix (e.g. the glob `**/*.Dockerfile`), not an anchored regex bound to a single literal filename.

**Experience context:** A CI engineer or maintainer asking *"are the image's apt package versions kept current automatically?"* relies on Renovate opening weekly PRs for curl, git, lcov, ca-certificates, unzip, ruby-full, build-essential, openjdk-17-jdk-headless, and sudo. Before this requirement, the manager's pattern (`/^Dockerfile$/`) matched no file after the `Dockerfile → android.Dockerfile` rename, so every pin silently went stale with no signal. Binding the pattern to the `*.Dockerfile` suffix rather than a literal name means a future rename or a new `*.Dockerfile` does not silently re-break automated pinning.

#### Scenario: Custom manager matches the renamed Dockerfile

- **GIVEN** the deb custom manager in `.github/renovate.json`
- **WHEN** Renovate evaluates the repository
- **THEN** its `managerFilePatterns` matches `android.Dockerfile`
- **AND** each `# renovate: depName=…` pin in that file is extracted as a `deb` dependency

#### Scenario: Pattern survives a Dockerfile rename or addition

- **GIVEN** a maintainer renames `android.Dockerfile` or adds a new `*.Dockerfile` carrying `# renovate:` apt pins
- **WHEN** Renovate evaluates the repository
- **THEN** the custom manager matches the file without any edit to `.github/renovate.json`

#### Scenario: A stale pin would have been caught

- **GIVEN** the custom manager matches `android.Dockerfile`
- **WHEN** an apt package pinned in that file has a newer version in any suite the image enables
- **THEN** Renovate opens an upgrade PR for that pin on its weekly schedule

### Requirement: Each `# renovate:` annotation names the dependency actually installed, with the correct datasource

Every `# renovate:` annotation in `android.Dockerfile` SHALL name, in its `depName`, the exact dependency that the corresponding `RUN` line installs, and SHALL use the datasource matching that dependency's ecosystem. A `deb`-ecosystem pin SHALL carry `depName` only; it SHALL NOT carry a `suite=` field, because the suites a pin resolves against are owned by `packageRules` in `.github/renovate.json`. A version value managed elsewhere (e.g. via the `config/version.json` manifest and a `--build-arg`) SHALL NOT carry a contradicting inline `# renovate:` annotation.

**Experience context:** A maintainer reading a pin trusts that Renovate is tracking *that* package, and that every field in the annotation still steers something. A wrong `depName` is worse than an unmatched pin: Renovate feeds the wrong dependency's version into the `ARG`, which can break the build (e.g. a `ruby-dev` version string applied to a `ruby-full` install) or silently track an unrelated project. A field that no longer steers anything is the same hazard in slower motion — the annotations carried `suite=bookworm` for ten weeks while every lookup went to `stable`, and reading the Dockerfile gave no hint of the discrepancy. The suite remains discoverable where it is genuinely decided: the `COPY config/debian_12_bookworm.sources` line in the stage that adds the repository, and the `~deb12uN` / `+deb13uN` marker carried by each pinned version string. The `fastlane` gem is intentionally not pinned here at all: its version is owned by `config/version.json` and fanned out to the build (`--build-arg fastlane_version`) and the rendered docs, so an inline `depName=fastlane` would be both wrong and redundant.

#### Scenario: deb pin names the installed package

- **GIVEN** the `RUBY_VERSION` pin, whose `RUN` line installs `ruby-full`
- **WHEN** a maintainer reads its `# renovate:` annotation
- **THEN** the `depName` is `ruby-full`, not `ruby-dev`

#### Scenario: A deb annotation carries no suite field

- **GIVEN** any `# renovate:`-annotated apt pin in `android.Dockerfile`
- **WHEN** a maintainer reads the annotation
- **THEN** it declares `depName` and nothing else
- **AND** no field in it is inert — every field it declares changes what Renovate does

#### Scenario: Manifest-managed gem is not double-pinned inline

- **GIVEN** the `fastlane` gem, whose version is owned by `config/version.json` and injected via `--build-arg fastlane_version`
- **WHEN** a maintainer scans `android.Dockerfile` for `# renovate:` annotations
- **THEN** no annotation names `fastlane` as a `depName`
- **AND** Renovate does not surface `fastlane` as a managed dependency of the Dockerfile
