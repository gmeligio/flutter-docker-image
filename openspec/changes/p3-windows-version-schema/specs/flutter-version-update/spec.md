## MODIFIED Requirements

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL satisfy `cue vet config/schema.cue -d '#Version'` and SHALL contain the Android `buildTools.version` listed for that exact Flutter tag in `engine/src/flutter/tools/android_sdk/packages.txt` upstream. The same `version.json` SHALL also contain a `windows.git.version` equal to the latest non-prerelease tag at `https://api.github.com/repos/git-for-windows/git/releases/latest` (with any `.windows.N` suffix stripped) and the VS BuildTools component versions sourced from the deterministic source documented in `p3-windows-version-schema`'s design.

The experience context is the CI engineer reviewing or merging the upgrade PR — they observe that downstream image builds will not silently regress on Android tooling *or* on Windows tooling.

#### Scenario: Build-tools version tracks the new Flutter tag

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at tag `X.Y.Z` lists `build-tools;A.B.C`
- **WHEN** the PR is created
- **THEN** `config/version.json` in the PR contains `android.buildTools.version == "A.B.C"`

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
