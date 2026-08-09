## ADDED Requirements

### Requirement: The Linux image build exists once, as a callable unit

The procedure for building the Linux image SHALL be defined once, in a reusable
workflow invoked via `workflow_call`. Every workflow that builds
`android.Dockerfile` SHALL call it rather than restate the build inline.

The callable unit SHALL own everything the legs have in common: the manifest
read, runner disk cleanup, Buildx setup, registry logins, image metadata, and the
`docker/build-push-action` invocation including its build arguments.

Callers SHALL declare only the dimensions in which their leg legitimately
differs — the build target, whether the result is pushed, which cache backend is
used, whether attestations are produced, and which registries are logged into.
A caller SHALL NOT restate a build argument.

This mirrors the boundary the Windows image build already uses
(`windows-image.yml:7-27`, called from `windows.yml:19` and `release.yml:131`),
so the repository has one pattern for "a build as a callable unit" rather than
two.

**Experience context:** A CI engineer trusts that the image validated on a pull
request is built the same way as the image published on release. Before this
requirement the same ~45-line build step was copy-pasted four times
(`build.yml` push path, `build.yml` fork path, `ci.yml`, `release.yml`) and had
already drifted: only `release.yml` passed `buildkitd-flags: --debug`, only
`release.yml` logged into Quay, `ci.yml` had no GHCR login, and only `build.yml`
requested attestations. Each divergence was invisible unless a maintainer diffed
four files by hand.

#### Scenario: Every Linux build leg runs the same procedure

- **GIVEN** the `build.yml` push path, the `build.yml` fork path, `ci.yml`, and `release.yml`
- **WHEN** a maintainer reads how each builds the image
- **THEN** each is a call to the reusable Linux image workflow
- **AND** no workflow file contains an inline `build-args:` block naming `flutter_version` or `android_ndk_version` for `android.Dockerfile`

#### Scenario: A change to the build procedure reaches every leg

- **GIVEN** a maintainer changes how the image is built — a new build argument, a different cache setting, an added label
- **WHEN** the change is made in the reusable workflow
- **THEN** all four legs build with it
- **AND** no leg can be left behind, because no leg carries its own copy

#### Scenario: Fork PR build receives the same arguments as a push build

- **GIVEN** a pull request from a fork, which builds but cannot push
- **WHEN** the fork build path runs
- **THEN** it receives the identical build-argument set as the push path
- **AND** the two paths cannot drift, because they call one workflow

#### Scenario: A leg's genuine difference is declared, not duplicated

- **GIVEN** `ci.yml` uses the `gha` cache backend and produces no attestations, while `build.yml` uses the registry cache and does
- **WHEN** each calls the reusable workflow
- **THEN** the difference is expressed as input values
- **AND** neither leg restates the build step to express it

### Requirement: Build arguments are declared where the Dockerfile they feed is named

The build arguments passed to `android.Dockerfile` SHALL be declared in the same
workflow that names that Dockerfile, and SHALL NOT be transported to it through a
shared environment value assembled elsewhere.

A workflow that builds `android.Dockerfile` SHALL NOT name any build argument
belonging to the Windows image (`git_version`, `vs_cmake_version`,
`vs_win11sdk_build`, `vs_vctools_version`).

Build-argument names SHALL be preserved exactly as currently declared. Renaming is
not in scope: each name is also an `ARG` in a Dockerfile, so a rename is a
coordinated multi-file change with no benefit to the person consuming the image.

**Experience context:** A maintainer reading the build sees which arguments reach
which Dockerfile without following an indirection. This matters because
`config/version.json` holds values for two different images, and two of them
collide by name once flattened: `windows.git.version` is the Git for Windows
release (`2.55.0`), while `android.Dockerfile:10` declares `ARG GIT_VERSION` as a
Debian apt pin (`1:2.47.3-0+deb13u1`) for a different tool with a different
version grammar. Keeping each image's arguments in the workflow that builds it
means the wrong value cannot be routed to the wrong build — and a mistake would
not be silent, since BuildKit only *warns* about a build argument no `ARG`
declares.

#### Scenario: Windows values cannot reach the Linux build

- **GIVEN** `config/version.json` contains both `windows.git.version` and the Linux image's values
- **WHEN** the Linux image is built
- **THEN** the build receives only the seven android build arguments
- **AND** no Windows-derived value appears on the resolved command line

#### Scenario: Established names are preserved exactly

- **GIVEN** the build moves into the reusable workflow
- **WHEN** the resolved `docker buildx build` command line is compared to the previous one for the same leg
- **THEN** the build-argument names and values are identical
- **AND** no `ARG` declaration in any Dockerfile required an edit

### Requirement: A manifest value that cannot be resolved fails before any build starts

`script/setEnvironmentVariables.js` SHALL fail with a named error when a manifest
path it reads does not resolve, rather than exporting an empty or `undefined`
value. It SHALL log the values it resolved, so a job log records what was passed.

**Experience context:** A maintainer who renames or removes a field in
`config/version.json` learns immediately, at the step that reads it, instead of
15 minutes later inside a Docker layer — or, in the worst case, not at all. The
worst case is real: the `web` stage (`android.Dockerfile:225`) declares none of
these arguments, so a wrong or empty value passed to a `web` build is silently
ignored rather than failing at a consuming `RUN`.

#### Scenario: Unresolvable manifest path fails the step

- **GIVEN** the emitter reads a path that `config/version.json` no longer contains
- **WHEN** the step runs
- **THEN** it fails with an error naming the path
- **AND** no image build starts

#### Scenario: Resolved values are visible in the job log

- **GIVEN** any workflow that reads the manifest
- **WHEN** the emitter step completes
- **THEN** the job log shows each manifest-derived value it resolved

### Requirement: The callable unit preserves per-argument layer caching

The reusable workflow SHALL pass one `--build-arg` flag per value. The manifest
SHALL NOT be passed as a single serialized build argument, and
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
