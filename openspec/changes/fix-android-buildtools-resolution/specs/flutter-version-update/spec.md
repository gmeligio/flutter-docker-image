## MODIFIED Requirements

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL satisfy `cue vet config/schema.cue -d '#Version'` and SHALL contain the Android `buildTools.version` that the Android Gradle Plugin (AGP) resolves inside a freshly-created Flutter project at the target Flutter tag. Specifically, after `flutter create test_app` runs against the target Flutter tag, the workflow SHALL read `buildToolsVersion` from the AGP DSL extension on the generated app module (the public API surface `com.android.build.api.dsl.ApplicationExtension.buildToolsVersion`) and write that exact string into `config/version.json`. The workflow SHALL NOT extract the build-tools version from Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` mirror manifest, because that file describes Google's CIPD pre-staging set, not what AGP requests at runtime, and the two have diverged since AGP 9.0. The same `version.json` SHALL also contain a `windows.git.version` equal to the latest non-prerelease tag at `https://api.github.com/repos/git-for-windows/git/releases/latest` (with any `.windows.N` suffix stripped) and the VS BuildTools component versions sourced from the deterministic source documented in `p3-windows-version-schema`'s design, as refined by `p11-resilient-windows-update`'s design (release-identity check against Microsoft's `channel.json` and `vsman.json`).

When the `update_windows_version` job has skipped its update for this cycle (because Microsoft's `channel.json` and `vsman.json` disagree on release identity), the PR SHALL still open with the Flutter and Android updates merged into `config/version.json` and the existing committed `windows` block carried forward unchanged. The PR body SHALL include a one-line annotation explaining that the Windows toolchain was unchanged this cycle. The carried-forward `windows` block SHALL pass `cue vet` against `#Version` because it was already valid on the base branch.

The experience context is the CI engineer reviewing or merging the upgrade PR — they observe that downstream image builds will not silently regress on Android tooling *or* on Windows tooling (in particular, that the smoke test `flutter create test_app && ./gradlew bundleRelease` does not trigger runtime `sdkmanager` downloads because the build-tools version pinned in the image matches the version AGP asks for), that an extractor bug cannot quietly produce a malformed `buildTools.version` that only surfaces as a confusing schema error, and that a transient inconsistency in Microsoft's VS manifest publishing does not block the Flutter+Android portion of the monthly upgrade.

#### Scenario: Build-tools version tracks the AGP default of the new Flutter tag

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** Flutter `X.Y.Z`'s templates pin AGP version `M.m.p`
- **AND** AGP `M.m.p`'s default `buildToolsVersion` is `A.B.C`
- **AND** Flutter `X.Y.Z`'s templates and Gradle plugin do not override `android.buildToolsVersion`
- **WHEN** the `update_android_version` job runs `flutter create test_app` and reads `buildToolsVersion` from the generated app module's AGP DSL extension
- **THEN** the read value is `A.B.C` exactly
- **AND** `config/version.json` in the resulting PR contains `android.buildTools.version == "A.B.C"`
- **AND** the workflow makes no network request to `raw.githubusercontent.com/flutter/flutter/.../packages.txt` for the purpose of resolving build-tools

#### Scenario: Build-tools version tracks an explicit template override when Flutter sets one

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** Flutter `X.Y.Z`'s app template (or `flutter_tools` Gradle plugin) explicitly sets `android.buildToolsVersion = "Q.R.S"` in the generated `build.gradle.kts`
- **WHEN** the `update_android_version` job reads `buildToolsVersion` from the AGP DSL extension on the generated app module
- **THEN** the read value is `Q.R.S` (the explicit override wins over AGP's default)
- **AND** `config/version.json` in the resulting PR contains `android.buildTools.version == "Q.R.S"`

#### Scenario: Pre-installed build-tools matches what a vanilla Flutter project requests

- **GIVEN** an image built from the PR's `config/version.json` has `android.buildTools.version == A.B.C` pre-installed at `/home/flutter/sdks/android-sdk/build-tools/A.B.C`
- **WHEN** a CI engineer runs `flutter create test_app && cd test_app/android && ./gradlew bundleRelease` inside the image
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
