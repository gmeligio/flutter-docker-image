## ADDED Requirements

### Requirement: Manifest values reach the Docker build by mechanical name derivation

`script/setEnvironmentVariables.js` SHALL derive each Docker build argument name
mechanically from its `config/version.json` path — the dot-path lowercased with
separators replaced by underscores and a trailing `.version` or `.build` segment
dropped (`android.ndk.version` → `android_ndk_version`,
`windows.vsBuildTools.vcTools.version` → `vs_vctools_version`). It SHALL NOT
require a hand-maintained entry per value for leaf shapes of the form
`{version: X}` or `{build: X}`.

Values whose manifest shape is not a scalar leaf (currently
`android.platforms`, an array joined into a space-separated string) SHALL be
declared in an explicit transformation table in that same script, so every
exception is visible in one place rather than implied by its absence.

**Experience context:** A maintainer adding a new pinned tool to the image edits
`config/version.json` and declares an `ARG` in the Dockerfile. They do not edit a
list of exports, and they do not edit any workflow. Before this requirement,
carrying one new value required five file edits across four workflows, which is
why `android.java.version` was left unwired and stale.

#### Scenario: Maintainer adds a new manifest value

- **GIVEN** a maintainer adds `android.foo.version` to `config/version.json`
- **AND** declares `ARG android_foo_version` in `android.Dockerfile`
- **WHEN** the image build runs
- **THEN** the build receives `--build-arg android_foo_version=<value>`
- **AND** no file under `.github/workflows/` was edited to achieve this
- **AND** `script/setEnvironmentVariables.js` was not edited to achieve this

#### Scenario: Nested Windows value derives its documented name

- **GIVEN** `config/version.json` contains `windows.vsBuildTools.vcTools.version`
- **WHEN** `script/setEnvironmentVariables.js` runs
- **THEN** the derived build-argument name is stable and documented in the script
- **AND** it matches the `ARG` name declared in `windows.Dockerfile`

#### Scenario: Non-scalar value is transformed through the explicit table

- **GIVEN** `config/version.json` has `android.platforms` as an array of objects
- **WHEN** `script/setEnvironmentVariables.js` runs
- **THEN** `android_platform_versions` is a space-separated list of the version values
- **AND** the transformation is declared in the script's explicit table, not inferred

### Requirement: Build arguments are emitted once and consumed identically by every Linux build

`script/setEnvironmentVariables.js` SHALL emit the complete set of manifest-derived
build arguments as a single environment value (`BUILD_ARGS`), formatted as
newline-separated `name=value` pairs. Every Linux image build in
`.github/workflows/` SHALL consume it as `build-args: ${{ env.BUILD_ARGS }}` and
SHALL NOT restate individual build arguments inline.

**Experience context:** A maintainer changing what the image is built with has one
place to look and one place to edit. Before this requirement the same six-line
block was copy-pasted four times (`build.yml` push path, `build.yml` fork path,
`ci.yml`, `release.yml`), kept in sync by hand — four opportunities for the legs to
silently disagree about what was built.

#### Scenario: All Linux build legs pass the same arguments

- **GIVEN** the `build.yml` push path, the `build.yml` fork path, `ci.yml`, and `release.yml`
- **WHEN** a maintainer reads their `build-args:` inputs
- **THEN** each is exactly `${{ env.BUILD_ARGS }}`
- **AND** no workflow file contains an inline `flutter_version=` or `android_ndk_version=` build-arg line

#### Scenario: Fork PR build receives the same arguments as a push build

- **GIVEN** a pull request from a fork, which builds but cannot push
- **WHEN** the fork build path runs
- **THEN** it receives the identical build-argument set as the push path
- **AND** the two paths cannot drift, because they read one value

### Requirement: Centralized emission preserves per-argument layer caching

The emitted `BUILD_ARGS` SHALL expand to one `--build-arg` flag per value. The
manifest SHALL NOT be passed as a single serialized build argument, and
`config/version.json` SHALL NOT be `COPY`-ed into any build stage for the purpose
of supplying versions.

**Experience context:** A CI engineer waiting on a build sees an unchanged tool
rebuild only when that tool's own version changed. Image builds take 15–25 minutes
and depend on registry build cache; collapsing the arguments into one value would
make every version bump invalidate every layer beneath it, so a Fastlane patch bump
would re-clone the Flutter SDK.

#### Scenario: Unrelated version bump reuses cached layers

- **GIVEN** a build whose only manifest change is `fastlane.version`
- **WHEN** the image is rebuilt with a warm cache
- **THEN** the Flutter clone layer is served from cache
- **AND** only the Fastlane layer and those after it are rebuilt

#### Scenario: Build command carries discrete arguments

- **GIVEN** any Linux image build
- **WHEN** the resolved `docker buildx build` command line is inspected in the job log
- **THEN** it contains one `--build-arg name=value` flag per manifest-derived value
- **AND** it contains no build argument whose value is a serialized JSON document
