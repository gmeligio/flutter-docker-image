# windows-image-testing Specification

## Requirements

### Requirement: Pull request CI verifies the Windows image on every PR

The `.github/workflows/windows.yml` workflow SHALL run on every `pull_request` event, build `windows.Dockerfile` with `--target test`, and run the Pester suite at `test/windows/Windows.Tests.ps1` inside that image. The workflow SHALL fail the PR check if the image build fails, if any Pester test fails, or if Pester exits non-zero.

The experience context is the maintainer reviewing a PR that touches `windows.Dockerfile`, `script/InstallPester.ps1`, `script/RunPester.ps1`, or `test/windows/**` — they get a single red/green check rather than having to build the multi-hour Windows image locally.

#### Scenario: PR check is green when the image is healthy

- **GIVEN** a PR whose `windows.Dockerfile` builds successfully on `windows-2025`
- **AND** every Pester test in `test/windows/Windows.Tests.ps1` passes inside the resulting `test`-target image
- **WHEN** the `test_windows` job runs
- **THEN** the job exits 0
- **AND** the `test_windows` check on the PR is reported as success

#### Scenario: PR check is red when a Pester test fails

- **GIVEN** a PR whose `test`-target image builds successfully
- **AND** at least one Pester test fails (e.g., the Flutter version inside the image does not match `config/version.json`)
- **WHEN** `script/RunPester.ps1` runs
- **THEN** the script exits non-zero (it propagates `$LASTEXITCODE` from `Invoke-Pester`)
- **AND** the `test_windows` job is reported as failed on the PR

#### Scenario: PR check is red when the Dockerfile cannot be built

- **GIVEN** a PR that breaks `windows.Dockerfile` (for example, by referencing a `COPY` source path that does not exist)
- **WHEN** the `test_windows` job runs `docker build ... --target test`
- **THEN** the build exits non-zero
- **AND** the `test_windows` job is reported as failed on the PR

### Requirement: Tests assert the Flutter version inside the image matches `config/version.json`

The Pester suite SHALL include a test that runs `flutter --version` inside the running container and asserts the reported semver equals `flutter.version` from `config/version.json` at the commit being tested. The version SHALL be read from the manifest, not hardcoded in the test file.

The experience context is the CI engineer pulling `flutter-windows:<tag>` and expecting the in-container Flutter to match the tag — a silent drift between manifest and image is the failure mode this requirement prevents.

#### Scenario: Manifest and image agree

- **GIVEN** `config/version.json` declares `flutter.version == "X.Y.Z"`
- **AND** the image was built with `--build-arg flutter_version=X.Y.Z`
- **WHEN** the Flutter version Pester test runs
- **THEN** `flutter --version` inside the container reports `Flutter X.Y.Z`
- **AND** the test passes

#### Scenario: Manifest and image disagree

- **GIVEN** `config/version.json` declares `flutter.version == "X.Y.Z"`
- **AND** the image was built with `--build-arg flutter_version=X.Y.W` (any other version)
- **WHEN** the Flutter version Pester test runs
- **THEN** the test fails with a message naming both versions

### Requirement: Tests assert `flutter doctor` reports a healthy Windows toolchain

The Pester suite SHALL include a test that runs `flutter doctor` inside the container and applies a per-line rule based on the platform header:

- Lines whose header is `Android`, `iOS`, `macOS`, `Linux`, `Web`, or `Chrome` SHALL be skipped (these platforms are explicitly disabled by `flutter config --no-enable-*` in `windows.Dockerfile`).
- Lines whose header starts with `Windows Version` or `Visual Studio` SHALL fail the test unless the marker is `[✓]`. Both `[!]` (partial) and `[✗]` (missing) on these two lines indicate a real toolchain regression — `WindowsVersionValidator` and `VisualStudioValidator` in `flutter/flutter` emit `[!]` for conditions such as Topaz OFD interference, missing required VS components, missing Windows 10 SDK, incomplete install, or VS too old.
- All other lines (e.g., `Flutter`, `Connected device`, `Network resources`) SHALL fail only on `[✗]`. `[!]` on these is informational in a CI container.

The experience context is the developer who runs `docker run flutter-windows flutter doctor` after pulling the image and expects a clean report for the Windows desktop toolchain — Pester catches regressions before the image is published.

#### Scenario: Doctor reports a clean Windows toolchain

- **GIVEN** the image was built successfully with VS BuildTools (CMake, Win11SDK, VCTools workload) installed
- **WHEN** the doctor Pester test runs
- **THEN** `flutter doctor` reports `[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps`
- **AND** the test passes

#### Scenario: Doctor reports a Windows-toolchain hard error

- **GIVEN** a PR that removes the `Microsoft.VisualStudio.Workload.VCTools` line from `windows.Dockerfile`
- **AND** the image still builds (the workload removal does not break the build itself)
- **WHEN** the doctor Pester test runs
- **THEN** `flutter doctor` reports `[✗] Visual Studio` (or equivalent missing-toolchain marker)
- **AND** the test fails

#### Scenario: Doctor reports a Windows-toolchain partial install

- **GIVEN** a PR that removes the `Microsoft.VisualStudio.Component.Windows11SDK.22621` line from `windows.Dockerfile`
- **AND** the image still builds and Visual Studio itself is still present
- **WHEN** the doctor Pester test runs
- **THEN** `flutter doctor` reports `[!] Visual Studio - develop Windows apps` (partial: missing required component)
- **AND** the test fails

#### Scenario: Doctor warning on a non-toolchain line is tolerated

- **GIVEN** the image was built successfully and `flutter doctor` reports `[!] Connected device` (no devices connected — expected in CI)
- **WHEN** the doctor Pester test runs
- **THEN** the `Connected device` line is classified as informational
- **AND** the test passes

### Requirement: Tests assert presence of pinned Visual Studio components

The Pester suite SHALL assert that the directories at `$env:ProgramData\Microsoft\VisualStudio\Packages\` contain entries matching the components installed by `windows.Dockerfile`: `Microsoft.VisualStudio.Component.VC.CMake.Project`, `Microsoft.VisualStudio.Component.Windows11SDK.22621`, and `Microsoft.VisualStudio.Workload.VCTools`. The match pattern SHALL accept any installed `version=...` suffix.

The experience context is detecting silent removal or rename of a VS component in the Dockerfile — the package directory is the on-disk evidence that the component installed.

#### Scenario: All three components match

- **GIVEN** the image was built from the current `windows.Dockerfile`
- **WHEN** the VS-component Pester tests run
- **THEN** each of `VC.CMake.Project`, `Windows11SDK.22621`, and `Workload.VCTools` matches `*,version=*`
- **AND** all three tests pass

#### Scenario: Pattern correctly accepts the on-disk format

- **GIVEN** a real package directory `Microsoft.VisualStudio.Component.VC.CMake.Project,version=17.13.35919.96`
- **WHEN** the `BeLikeExactly` assertion runs against pattern `Microsoft.VisualStudio.Component.VC.CMake.Project,version=*`
- **THEN** the assertion passes

### Requirement: Tests assert Flutter and Dart telemetry are disabled

The Pester suite SHALL assert that the dart-flutter telemetry config at `$env:APPDATA\.dart-tool\dart-flutter-telemetry.config` exists and contains `reporting=0`.

The experience context is the privacy-conscious user pulling the image and expecting analytics to be off by default — the test prevents a Dockerfile change from silently re-enabling telemetry.

#### Scenario: Telemetry is disabled

- **GIVEN** the image was built with `flutter config --no-analytics; dart --disable-analytics;` as currently in `windows.Dockerfile`
- **WHEN** the telemetry Pester test runs
- **THEN** `dart-flutter-telemetry.config` contains `reporting=0`
- **AND** the test passes

### Requirement: The `test` Dockerfile stage is self-running by default

The `test` stage of `windows.Dockerfile` SHALL declare a `CMD` (or equivalent) that invokes `script/RunPester.ps1`, so that `docker run <test-image>` (and `docker compose run windows-test`) executes the Pester suite without requiring the caller to pass a command.

The experience context is the contributor who runs the test image locally — they should not need to know the exact PowerShell incantation to invoke Pester.

#### Scenario: Local invocation runs the suite

- **GIVEN** a test image built with `docker compose build windows-test`
- **WHEN** the contributor runs `docker compose run --rm windows-test`
- **THEN** Pester executes against `.\test`
- **AND** the container exits with the Pester exit code

### Requirement: No dead Go/dockertest harness in `test/windows/`

The repository SHALL NOT contain a Go module under `test/windows/` unless that module is invoked by at least one CI job. The `ory/dockertest` skeleton (`main.go`, `main_test.go`, `go.mod`, `go.sum`) introduced in commit `df7666e` SHALL be removed because Pester running inside the container is the chosen verification mechanism.

The experience context is the contributor reading `test/windows/` and trying to determine which file is the source of truth — a dead harness alongside live Pester tests is a confusion hazard.

#### Scenario: Repository contains no orphan Go test files for Windows

- **WHEN** a contributor lists `test/windows/`
- **THEN** the listing contains `Windows.Tests.ps1` (and any newly added Pester files)
- **AND** the listing does not contain `main.go`, `main_test.go`, `go.mod`, or `go.sum`
