# flutter-version-update Specification

## Purpose

The scheduled `update-version.yml` workflow opens monthly upgrade pull requests that bump the pinned Flutter stable release together with the Android and Windows toolchain blocks in `config/version.json`. The capability covers when an upgrade PR opens, what the PR's `version.json` must contain to be coherent and schema-valid, how each producer job validates its own output before handoff, how producer-job failure surfaces in the Actions tab, and how partial-update cycles (Windows-skip, Android-skip) carry the corresponding block forward from the base branch unchanged.
## Requirements
### Requirement: Scheduled run opens an upgrade PR when a new stable Flutter is released

The `update-version.yml` workflow SHALL open exactly one pull request titled `chore(release): upgrade flutter to <version>` whenever the latest entry in `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` matching the stable channel and a `\d+.\d+.\d+` version differs from the version currently pinned in `config/flutter_version.json`.

The experience context is the CI engineer who watches this repository for upgrade PRs to merge into their image fork.

#### Scenario: Upstream ships a new stable Flutter

- **GIVEN** `config/flutter_version.json` pins Flutter `X.Y.Z`
- **AND** the latest stable release in `releases_linux.json` is `X.Y.Z+1`
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** a branch `update-flutter-dependencies/X.Y.Z+1` is pushed
- **AND** a pull request is opened with title `chore(release): upgrade flutter to X.Y.Z+1`
- **AND** the commit message on that PR equals the title (non-empty)

#### Scenario: No upstream change since last run

- **GIVEN** `config/flutter_version.json` already pins the latest stable Flutter version
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** no branch is created
- **AND** no pull request is opened
- **AND** all jobs after `update_flutter_version` are skipped

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

### Requirement: Producer jobs validate their own `version.json` before upload

Each job in `update-version.yml` that writes to `config/version.json` and uploads it as an artifact SHALL run `cue vet config/schema.cue -d '#Version' config/version.json` (or `-d '#FlutterVersion'` for the flutter-only artifact) immediately before the upload step and SHALL fail that job on validation error.

The experience context is the CI engineer triaging a failed scheduled run — they see the failing job pointing at the step that produced the bad data, rather than a downstream `validate_config_version` failure that blames the schema without naming the producer.

#### Scenario: Android producer catches its own bad output

- **GIVEN** the `update_android_version` job writes a `config/version.json` whose `android.buildTools.version` does not match `^\d+\.\d+\.\d+$`
- **WHEN** the job's validation step runs before artifact upload
- **THEN** `cue vet` exits non-zero and the `update_android_version` job is marked failed
- **AND** the artifact upload step does not execute
- **AND** the downstream `validate_config_version` job is skipped, not blamed

#### Scenario: Producer validation passes for a well-formed manifest

- **GIVEN** the `update_android_version` job produces a `config/version.json` that satisfies `#Version`
- **WHEN** the job's validation step runs
- **THEN** `cue vet` exits 0
- **AND** the artifact upload step runs and uploads `config/version.json`

### Requirement: Schema rejects non-stable Flutter channels

`config/schema.cue` SHALL constrain `flutter.channel` to the literal `"stable"`. Any `flutter_version.json` whose channel is anything else SHALL fail `cue vet`.

The experience context is the CI engineer running schema validation locally (or via the `build.yml` validation step) — they get an immediate, loud failure if a non-stable release leaks into the manifest.

#### Scenario: Non-stable channel fails validation

- **GIVEN** a `flutter_version.json` with `flutter.channel == "beta"`
- **WHEN** `cue vet config/schema.cue -d '#FlutterVersion' config/flutter_version.json` runs
- **THEN** the command exits non-zero with a constraint-violation error on `flutter.channel`

#### Scenario: Schema itself is well-formed

- **GIVEN** the current `config/schema.cue`
- **WHEN** `cue vet config/schema.cue -d '#FlutterVersion' config/flutter_version.json` runs against the committed `config/flutter_version.json`
- **THEN** the command exits 0
- **AND** no `reference "#PatchVersion" not found` (or any other undefined-reference) error is produced

### Requirement: A failed update run surfaces as a failed workflow

If any step in the update pipeline (release fetch, schema validation, build-tools lookup, PR creation) fails, the workflow SHALL exit non-zero so the CI engineer sees a red run in the Actions tab rather than a silent no-op.

The experience context is the on-call CI engineer scanning the repository's Actions tab — they need silent failures (e.g. "ran but did nothing") to be impossible for failure modes other than "no upstream change."

#### Scenario: Release fetch fails

- **GIVEN** `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` is unreachable
- **WHEN** the scheduled run executes
- **THEN** the `update_flutter_version` job fails (red in Actions tab)
- **AND** no PR is opened

#### Scenario: Generated config fails schema validation

- **GIVEN** the workflow generated a `config/version.json` that violates `#Version`
- **WHEN** `validate_config_version` runs
- **THEN** the job fails
- **AND** the `update_docs_and_create_pr` job is skipped, so no PR is opened

#### Scenario: A "no upstream change" run is green, not red

- **GIVEN** the upstream stable Flutter version equals the pinned version
- **WHEN** the scheduled run executes
- **THEN** the workflow finishes with status success (green)
- **AND** the only completed job is `update_flutter_version`

