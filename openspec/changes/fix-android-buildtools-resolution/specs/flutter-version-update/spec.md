## MODIFIED Requirements

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL satisfy `cue vet config/schema.cue -d '#Version'`. Its `android.buildTools.version` SHALL equal the build-tools version that the Android Gradle Plugin (AGP) requests at build time inside a freshly-created Flutter project at the target Flutter tag — that is, the same version `sdkmanager` would install if `./gradlew bundleRelease` were run against a vanilla `flutter create` output. The workflow SHALL NOT derive this value from Flutter's `engine/src/flutter/tools/android_sdk/packages.txt`; that file lists Google's pre-staged CIPD package set and is not authoritative for what AGP requests. Its `windows.git.version` SHALL equal the latest non-prerelease tag at `https://api.github.com/repos/git-for-windows/git/releases/latest` (with any `.windows.N` suffix stripped). Its VS BuildTools component versions SHALL come from the deterministic source documented in `p3-windows-version-schema`'s design, as refined by `p11-resilient-windows-update`'s design (release-identity check against Microsoft's `channel.json` and `vsman.json`).

When the `update_windows_version` job has skipped its update for this cycle (because Microsoft's `channel.json` and `vsman.json` disagree on release identity), the PR SHALL still open with the Flutter and Android updates merged into `config/version.json` and the existing committed `windows` block carried forward unchanged. The PR body SHALL include a one-line annotation explaining that the Windows toolchain was unchanged this cycle. The carried-forward `windows` block SHALL pass `cue vet` against `#Version` because it was already valid on the base branch.

The experience context is the CI engineer reviewing or merging the upgrade PR. They observe that downstream image builds will not silently regress on Android tooling *or* on Windows tooling — in particular, that the image's pre-installed build-tools matches what a freshly-created Flutter project asks for, so the Android smoke test does not trigger runtime `sdkmanager` downloads. They also observe that an extractor bug cannot quietly produce a malformed `buildTools.version` that surfaces only as a confusing schema error downstream, and that a transient inconsistency in Microsoft's VS manifest publishing does not block the Flutter+Android portion of the monthly upgrade.

#### Scenario: Build-tools version tracks what AGP requests for the new Flutter tag

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** at tag `X.Y.Z`, `flutter create test_app` produces an Android project whose AGP configuration resolves `buildToolsVersion` to `A.B.C`
- **WHEN** the `update_android_version` job runs
- **THEN** `config/version.json` in the resulting PR contains `android.buildTools.version == "A.B.C"`
- **AND** the workflow makes no network request to `raw.githubusercontent.com/.../packages.txt` for the purpose of resolving build-tools

#### Scenario: Pre-installed build-tools matches what a vanilla Flutter project requests

- **GIVEN** an image built from the PR's `config/version.json` with `android.buildTools.version == A.B.C` pre-installed at `/home/flutter/sdks/android-sdk/build-tools/A.B.C`
- **WHEN** `flutter create test_app && cd test_app/android && ./gradlew bundleRelease` runs inside the image
- **THEN** Gradle completes the build without invoking `sdkmanager` to install or download any build-tools package
- **AND** the build output contains no occurrence of `Checking the license for package Android SDK Build-Tools`, `Installing Android SDK Build-Tools`, or `Downloading https://dl.google.com/android/repository/build-tools_`
- **AND** the `test/android.yml` smoke test "Gradle, licenses and platforms are already downloaded" passes

#### Scenario: Generated config is schema-valid

- **GIVEN** the workflow has produced a candidate `config/version.json`
- **WHEN** the `validate_config_version` job runs
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- **AND** the workflow only proceeds to open the PR if validation passes

#### Scenario: Git for Windows tracks the latest published tag

- **GIVEN** `https://api.github.com/repos/git-for-windows/git/releases/latest` returns an asset whose underlying Git semver is `M.m.p`
- **WHEN** the upgrade PR is created
- **THEN** `config/version.json` in the PR contains `windows.git.version == "M.m.p"`

#### Scenario: Windows toolchain block is schema-valid

- **GIVEN** the workflow has produced a candidate `config/version.json` containing the new `windows` block
- **WHEN** the `validate_config_version` job runs
- **THEN** `cue vet` passes against the `windows` block as well as the existing `flutter` and `android` blocks

#### Scenario: PR opens with Windows toolchain unchanged when upstream is inconsistent

- **GIVEN** the `update_windows_version` job skipped its update this cycle because Microsoft's `channel.json` and `vsman.json` disagreed on release identity
- **AND** the `update_flutter_version` and `update_android_version` jobs produced fresh artifacts
- **WHEN** the upgrade PR is composed
- **THEN** the PR opens with Flutter and Android updates merged into `config/version.json`
- **AND** the `windows` block in the PR's `config/version.json` is byte-for-byte identical to the `windows` block on the base branch
- **AND** the PR body contains an annotation indicating the Windows toolchain was unchanged this cycle
- **AND** `cue vet config/schema.cue -d '#Version'` passes on the resulting `config/version.json`
