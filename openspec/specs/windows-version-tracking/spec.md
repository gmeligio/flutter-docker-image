# windows-version-tracking Specification

## Requirements

### Requirement: `config/version.json` declares the Windows toolchain versions

`config/version.json` SHALL contain a top-level `windows` object with the following fields, each validated by `config/schema.cue` `#Version`:

- `windows.git.version` — Git for Windows release version, three-part semver (e.g., `2.46.0`).
- `windows.vsBuildTools.cmakeProject.version` — Visual Studio CMake component version, four-part (e.g., `17.13.35919.96`).
- `windows.vsBuildTools.windows11Sdk.build` — Windows 11 SDK build number as integer (e.g., `22621`).
- `windows.vsBuildTools.vcTools.version` — Visual Studio VCTools workload version, four-part.

The experience context is the maintainer or CI engineer reading `config/version.json` to know exactly which Windows toolchain a given image tag was built against — without having to grep Dockerfiles.

#### Scenario: Manifest validates against schema

- **GIVEN** the current `config/version.json` and `config/schema.cue`
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits 0

#### Scenario: Missing `windows` block fails validation

- **GIVEN** a candidate `config/version.json` with no `windows` field
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits non-zero with an error naming the missing `windows` field

### Requirement: `windows.Dockerfile` builds from manifest values, not hardcoded constants

`windows.Dockerfile` SHALL accept the build args `flutter_version`, `git_version`, `vs_cmake_version`, `vs_win11sdk_build`, and `vs_vctools_version`, with no default values. The `--add Microsoft.VisualStudio.Component.Windows11SDK.${vs_win11sdk_build}` invocation in the Dockerfile SHALL substitute the build-arg value, and the Git installer download SHALL use the `git_version` build arg in the URL and filename.

The experience context is the contributor changing the Windows toolchain: they edit one place (`config/version.json`), regenerate, and the build picks up the change.

#### Scenario: Build with manifest values succeeds

- **GIVEN** `config/version.json` declares the four windows version fields
- **AND** `windows.yml` passes them as `--build-arg` from the env vars exported by `setEnvironmentVariables.js`
- **WHEN** the test_windows job runs `docker build`
- **THEN** the build completes and the resulting image has VS components installed at the manifest-declared versions

#### Scenario: Build without manifest values fails fast

- **WHEN** a developer runs `docker build -f windows.Dockerfile .` without any `--build-arg`
- **THEN** the build fails on the first ARG-using step
- **AND** the error message names the missing build argument

### Requirement: `setEnvironmentVariables.js` exports Windows fields as env vars

`script/setEnvironmentVariables.js` SHALL read `windows.git.version`, `windows.vsBuildTools.cmakeProject.version`, `windows.vsBuildTools.windows11Sdk.build`, and `windows.vsBuildTools.vcTools.version` from `config/version.json` and export them as `GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, and `VS_VCTOOLS_VERSION` to the GitHub Actions environment.

The experience context is `windows.yml` and `release.yml` reading exactly the same env vars to feed `docker build` — a single point of plumbing.

#### Scenario: Workflow env contains the windows fields

- **WHEN** the `Read environment variables from the version manifest` step runs in any workflow
- **THEN** the workflow's environment contains `GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, `VS_VCTOOLS_VERSION` with values matching `config/version.json`

### Requirement: Pester suite asserts exact toolchain versions

The Pester suite at `test/windows/Windows.Tests.ps1` SHALL read `config/version.json` (already copied into the test stage by `p1-fix-windows-ci-tests`) and assert that:

- `git --version` reports a version equal to `windows.git.version`,
- the `Microsoft.VisualStudio.Component.VC.CMake.Project,version=<x>` directory's `<x>` equals `windows.vsBuildTools.cmakeProject.version`,
- the `Microsoft.VisualStudio.Component.Windows11SDK.<build>` directory's `<build>` equals `windows.vsBuildTools.windows11Sdk.build`,
- the `Microsoft.VisualStudio.Workload.VCTools,version=<x>` directory's `<x>` equals `windows.vsBuildTools.vcTools.version`.

The experience context is the reviewer of an upgrade PR: any drift between the manifest the PR proposes and the image actually produced is caught as a hard test failure, not silent semantics drift.

#### Scenario: Manifest and image agree on every Windows version

- **GIVEN** the test image was built with the build args derived from the current `config/version.json`
- **WHEN** the Pester suite runs
- **THEN** all four version assertions pass

#### Scenario: Manifest claims a version the image does not have

- **GIVEN** a PR that bumps `windows.git.version` to a version different from the build arg actually passed to the image
- **WHEN** the Pester suite runs
- **THEN** the Git version test fails with a message naming both the manifest value and the in-image value

### Requirement: Monthly upgrade PR includes Windows toolchain updates

The `update_version.yml` workflow SHALL include a job that updates the `windows` block in `config/version.json` whenever it runs. The job SHALL:

- read the latest Git for Windows release from `https://api.github.com/repos/git-for-windows/git/releases/latest` and write the resolved version to `windows.git.version`,
- write the VS BuildTools component versions from a deterministic source (see design — channel manifest or pinned config),
- emit a CUE-validated `config/version.json` that is consumed by `validate_config_version` and `update_docs_and_create_pr`.

The experience context is the maintainer who merges the monthly upgrade PR and expects both Android and Windows toolchains to be bumped in the same PR — a single review surface.

#### Scenario: Monthly run produces a Windows-aware upgrade PR

- **GIVEN** a scheduled run of `update_version.yml` where Flutter has a new stable
- **AND** Git for Windows has a new release since the last run
- **WHEN** the workflow opens its upgrade PR
- **THEN** the PR's `config/version.json` has a bumped `windows.git.version`
- **AND** the PR's `config/version.json` passes `cue vet` against `#Version`

#### Scenario: No Windows update needed in this cycle

- **GIVEN** Git for Windows and VS BuildTools component versions match what is already in `config/version.json`
- **WHEN** the upgrade PR is composed
- **THEN** the PR still opens (because Flutter changed) but the `windows` block is unchanged byte-for-byte
