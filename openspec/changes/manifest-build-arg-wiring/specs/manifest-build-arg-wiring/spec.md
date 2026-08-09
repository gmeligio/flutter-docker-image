## ADDED Requirements

### Requirement: One declared table maps manifest paths to build-argument names

`script/setEnvironmentVariables.js` SHALL carry a single declarative table mapping
each `config/version.json` path to its Docker build-argument name, and SHALL derive
every export from that table rather than from a hand-written
`core.exportVariable` call per value.

The mapping SHALL NOT be described as a mechanical transformation of the JSON
path. It is not one: the established names drop path segments
(`android.cmake.version` → `cmake_version`, `windows.git.version` →
`git_version`), abbreviate them (`windows.vsBuildTools.cmakeProject.version` →
`vs_cmake_version`), and retain the trailing `version`/`build` segment
(`android.ndk.version` → `android_ndk_version`). No rule generates that set, and a
rule that generated a *different* set would rename every existing `ARG`.

The table SHALL preserve the current names exactly. Renaming build arguments is
not in scope: each name is also declared as an `ARG` in a Dockerfile, so a rename
is a coordinated multi-file change with no benefit to the person consuming the
image.

Values whose manifest shape is not a scalar leaf SHALL declare a transform in the
same table (currently only `android.platforms`, an array of `{version}` objects
joined into a space-separated string).

**Experience context:** A maintainer adding a new pinned tool to the image edits
`config/version.json`, adds one row to the table, and declares an `ARG` in the
Dockerfile. They do not edit any workflow. Before this requirement, carrying one
new value required five file edits across four workflows — which is why
`android.java.version` was left unwired and stale, reported by the manifest but
unable to influence the image.

#### Scenario: Adding a manifest value costs one table row

- **GIVEN** a maintainer adds `android.foo.version` to `config/version.json`
- **AND** adds the row mapping it to `android_foo_version` in the table
- **AND** declares `ARG android_foo_version` in `android.Dockerfile`
- **WHEN** the image build runs
- **THEN** the build receives `--build-arg android_foo_version=<value>`
- **AND** no file under `.github/workflows/` was edited to achieve this

#### Scenario: Established names are preserved exactly

- **GIVEN** the table-driven emitter replaces the hand-written exports
- **WHEN** the resolved `docker buildx build` command line is compared to the previous one
- **THEN** the build-argument names and values are identical
- **AND** no `ARG` declaration in any Dockerfile required an edit

#### Scenario: Non-scalar value is transformed through a declared transform

- **GIVEN** `config/version.json` has `android.platforms` as an array of objects
- **WHEN** the emitter runs
- **THEN** `android_platform_versions` is a space-separated list of the version values
- **AND** the transform is declared in the table, not inferred from the shape

### Requirement: Build arguments are emitted once and consumed identically by every Linux build

`script/setEnvironmentVariables.js` SHALL emit the manifest-derived build
arguments as a single environment value (`BUILD_ARGS`), formatted as
newline-separated `name=value` pairs. Every Linux image build in
`.github/workflows/` SHALL consume it as `build-args: ${{ env.BUILD_ARGS }}` and
SHALL NOT restate individual manifest-derived build arguments inline.

Exports that are not manifest-derived SHALL continue to be exported under their
own names, because steps other than the build read them from the environment:
`FLUTTER_VERSION` (read by tagging and test steps) and `IMAGE_REPOSITORY_PATH`
(composed from repository context, not from the manifest at all).

The Windows image build is out of scope. It assembles a PowerShell argument array
rather than using `docker/build-push-action`
(`windows-image.yml:130-149`), so it needs a different shape; the four duplicated
Linux blocks are what this change targets.

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

#### Scenario: Non-manifest exports survive the change

- **GIVEN** steps that read `FLUTTER_VERSION` or `IMAGE_REPOSITORY_PATH` from the environment
- **WHEN** the emitter runs
- **THEN** both are still exported under their own names
- **AND** those steps require no edit

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
