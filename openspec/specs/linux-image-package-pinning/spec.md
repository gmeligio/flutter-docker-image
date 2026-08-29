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
- **AND** each `# renovate: depName=…` pin in that file is extracted as a `deb` dependency

#### Scenario: Pattern survives a Dockerfile rename or addition

- **GIVEN** a maintainer renames `android.Dockerfile` or adds a new `*.Dockerfile` carrying `# renovate:` apt pins
- **WHEN** Renovate evaluates the repository
- **THEN** the custom manager matches the file without any edit to `.github/renovate.json`

#### Scenario: A stale pin would have been caught

- **GIVEN** the custom manager matches `android.Dockerfile`
- **WHEN** an apt package pinned in that file has a newer version in any suite the image enables
- **THEN** Renovate opens an upgrade PR for that pin on its weekly schedule

### Requirement: Self-pinned image version values are declared with `ARG`, never `ENV`

Every Renovate-managed `*_VERSION` value in `android.Dockerfile` — a value carrying a `# renovate:` annotation and a literal default — SHALL be declared with `ARG`, not `ENV`. The `matchStrings` regex SHALL remain `ARG`-only, so the convention is enforced by what Renovate can match: an `ENV`-declared pin is invisible to the manager and therefore a defect.

A runtime environment variable MAY interpolate a build argument into its value
(for example `JAVA_HOME="/usr/lib/jvm/java-${android_java_version}-openjdk-amd64"`).
This does not violate the convention: the version is still `ARG`-declared and
Renovate-visible where it is managed, and the `ENV` is a derived runtime path
rather than a second pin. Such an `ENV` SHALL NOT introduce a literal version that
duplicates a value already carried by a build argument, and the interpolated `ARG`
SHALL be declared before the `ENV` that consumes it.

The allowance is bounded on both sides, and the boundary is the point of the
requirement rather than an incidental consequence of it. An `ENV` MAY interpolate
an `ARG` only when **both** hold: the `ENV` is a runtime path or setting the image
must expose for a tool to function, and the `ARG` it interpolates is not itself a
Renovate-managed `*_VERSION` pin. A `# renovate:`-annotated pin SHALL NOT reach an
`ENV` by any route — neither as a literal nor by interpolation. Interpolating one
would put the pin in the image's `Env` and in `docker inspect` output, which is
exactly what the `ARG`-only rule exists to prevent; the rule would otherwise be
trivially circumventable by wrapping the pin in an `ENV`.

`JAVA_HOME` satisfies both conditions: Gradle and the Android toolchain read it
from the environment, and `android_java_version` is a major supplied from the
manifest via `--build-arg`, not a pin. `OPENJDK_17_JDK_HEADLESS_VERSION` satisfies
neither and stays confined to the `RUN` that consumes it, as do the other eight
apt pins.

**Experience context:** A maintainer reading `android.Dockerfile` sees one keyword convention for self-pinned versions, with no `ENV` exceptions to explain. Build-only version strings do not leak into the final image's runtime environment or `docker inspect` metadata, and cannot collide with a real runtime variable a tool might read from the environment. Runtime variables that a tool genuinely needs — `JAVA_HOME` is read by Gradle and the Android toolchain — remain `ENV`, but derive their version component from the build argument rather than restating it, so the image cannot ship a `JAVA_HOME` pointing at a JDK major different from the one installed. The uppercase/lowercase `ARG` distinction is preserved and orthogonal: UPPERCASE-with-default names are self-pinned and Renovate-managed; lowercase names without a default are injected at build time via `--build-arg` from CI and are intentionally outside Renovate's scope.

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

#### Scenario: Runtime path derives its version from a build argument

- **GIVEN** `android.Dockerfile` declares `ARG android_java_version` supplied via `--build-arg`
- **WHEN** a maintainer reads the `JAVA_HOME` assignment
- **THEN** it interpolates `${android_java_version}` rather than a literal JDK major
- **AND** the `ARG` is declared before the `ENV` that consumes it
- **AND** the built image's `JAVA_HOME` resolves to the JDK major that was actually installed

#### Scenario: A managed pin cannot reach ENV by interpolation

- **GIVEN** a `# renovate:`-annotated `*_VERSION` `ARG` such as `OPENJDK_17_JDK_HEADLESS_VERSION`
- **WHEN** a maintainer reads `android.Dockerfile`
- **THEN** no `ENV` interpolates it
- **AND** it appears only in the `RUN` instruction that consumes it
- **AND** `docker inspect` on the built image shows it in neither `Env` nor any derived `Env` value

#### Scenario: No literal duplicates a build-argument value

- **GIVEN** a version value carried by a build argument
- **WHEN** a maintainer greps `android.Dockerfile` for that version as a literal
- **THEN** it appears only in the Renovate-managed `ARG` default, if at all
- **AND** no `ENV` restates it

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

### Requirement: Each apt pin resolves against the same set of Debian suites the image enables

Every `deb`-datasource pin SHALL be resolved against the Debian suites from which the
installing image stage can install it — at minimum the base suite and its `-security` suite —
expressed as a list of `registryUrls` on a `packageRules` entry in `.github/renovate.json`.
Each `registryUrls` entry SHALL mirror a `Types`/`URIs`/`Suites`/`Components` stanza of the
image's real apt sources, in both suite and component list. Suite selection SHALL NOT be
expressed via `registryUrlTemplate`, which renders a single URL and therefore cannot address a
set.

Where a listed suite cannot currently be fetched by Renovate, the configuration SHALL record
why in its `description`, naming the upstream limitation, so that a maintainer reading the
config can tell an intentional gap from an oversight.

**Experience context:** A CI engineer trusts that a Renovate PR bumping an apt pin produces a
version the image can actually install. apt picks the highest version across every enabled
suite, so if Renovate watches fewer suites than apt, the two disagree about what "latest" is.

`-security` is load-bearing, not merely a currency concern. The only installable version of
`openjdk-17-jdk-headless` is `17.0.20.1+1-1~deb12u1`, published in `bookworm-security` and
nowhere else: a security upload moved `openjdk-17-jre-headless` there, and the JDK's strict
`Depends: openjdk-17-jre-headless (= <same version>)` forces the JDK to follow. A configuration
omitting the `-security` suite would state that the pin comes from somewhere it does not, and
could never propose the version the image needs.

Renovate cannot currently fetch those suites: its deb datasource hardcodes
`const compression = 'gz'`, and Debian publishes only `Packages` and `Packages.xz` on
`-security` and `-updates`, so each such URL returns 404 on every run — swallowed at debug
level while the job reports success. This is upstream renovate#44330; no repository
configuration works around it, and no mirror still carries the `.gz`. The `-security` entries
are kept regardless, because they state correctly where the pin resolves from and will resume
working with no edit once upstream lands `.xz`. The `-updates` entries are dropped: they are
equally unfetchable and no current pin resolves from them, so they assert coverage with no
corresponding need.

While that gap persists, Renovate cannot be relied on to notice a pin that has stopped being
installable. What catches it is the image build itself: editing a pin changes the Dockerfile,
which invalidates the build cache and re-runs `apt-get install`, so a bad pin fails the PR that
introduces it. A pin can still rot with no repo change — a later security upload moves apt's
candidate — and that break surfaces on the next PR to touch the file rather than when it
happens. That delay is accepted.

#### Scenario: A pin is resolved against the base and security suites of its family

- **GIVEN** an apt pin in `android.Dockerfile` installed from a suite the image enables
- **WHEN** a maintainer reads the configured `registryUrls` for that pin
- **THEN** they name the base suite and its `-security` suite
- **AND** together they describe where apt actually resolves the package from

#### Scenario: A pin installed from an added repository resolves against that repository

- **GIVEN** `openjdk-17-jdk-headless`, which the android stage installs after adding `config/debian_12_bookworm.sources`
- **WHEN** Renovate looks it up
- **THEN** it queries the bookworm suites named in that sources file, not the base image's trixie suites

#### Scenario: A known upstream fetch limitation is documented, not silent

- **GIVEN** a configured suite Renovate cannot currently fetch
- **WHEN** a maintainer reads the deb `packageRules` in `.github/renovate.json`
- **THEN** the `description` names the upstream limitation preventing it from being fetched
- **AND** the entry is recognisable as an intentional gap rather than a stale mistake

#### Scenario: A pin edited to an uninstallable version fails its own pull request

- **GIVEN** a pull request that changes an apt pin to a version apt cannot install
- **WHEN** the image is built for that pull request
- **THEN** the changed Dockerfile invalidates the build cache, `apt-get install` re-runs, and the build fails
- **AND** the failure names the version and the unmet dependency, so the pin is corrected before merge

#### Scenario: Suites are named by codename, not by a moving alias

- **GIVEN** the deb `packageRules` in `.github/renovate.json`
- **WHEN** a maintainer reads the configured suites
- **THEN** each names a Debian codename (e.g. `trixie`, `bookworm-security`)
- **AND** none uses a floating alias such as `stable` or `oldstable`, which would silently retarget every pin when Debian promotes a new release

### Requirement: Renovate configuration is syntax-validated before it is pushed

`.github/renovate.json` SHALL be syntax-validatable through a documented repository task that a maintainer can run locally. That task SHALL NOT be duplicated as a CI job.

**Experience context:** A maintainer editing Renovate config wants to know the config parses before pushing, and the validator script for that already existed in `script/` — unreferenced by any task, workflow or doc, and without an executable bit, so nothing could run it. Wiring it to a task closes that loop. It stays out of CI on purpose: Renovate config changes ship on a `renovate/reconfigure` branch, where the Renovate app validates the config itself and reports failures back, so a workflow running the same validator would add a job without adding a signal. The check is syntax-only either way — `renovate-config-validator` does not evaluate enum values or verify that a pin resolves against the right suite, so it catches malformed config, not wrong config.

#### Scenario: A maintainer validates config before pushing

- **GIVEN** a maintainer editing `.github/renovate.json`
- **WHEN** they run the repository's lint task
- **THEN** it validates the config and reports any syntax error, with no setup beyond the repository's own tooling

#### Scenario: Validation is not duplicated in CI

- **GIVEN** a Renovate config change pushed on a `renovate/reconfigure` branch
- **WHEN** it is opened for review
- **THEN** the Renovate app performs the authoritative validation and reports failures
- **AND** no repository workflow runs `renovate-config-validator` in addition
