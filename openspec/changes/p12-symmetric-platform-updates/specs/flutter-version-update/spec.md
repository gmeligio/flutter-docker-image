## MODIFIED Requirements

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL be a single composed manifest produced by the `compose_version_manifest` job and validated by `validate_config_version` before any PR work begins. The composed manifest SHALL satisfy `cue vet config/schema.cue -d '#Version'` and SHALL contain:

- the `flutter` block written by `update_flutter_version` (always present — the pipeline is gated on Flutter having changed),
- the `android` block written by `update_android_version` *if* that job produced its fragment artifact this cycle, otherwise the `android` block as committed on the base branch,
- the `windows` block written by `update_windows_version` *if* that job produced its fragment artifact this cycle, otherwise the `windows` block as committed on the base branch.

The job that creates the pull request (`update_docs_and_create_pr`) SHALL be a read-only consumer of the composed and validated manifest: it SHALL NOT run `jq` against `config/version.json`, SHALL NOT re-validate it, and SHALL NOT depend on the individual platform-updater jobs' artifacts.

When either platform updater skipped its update this cycle, the PR body SHALL include a one-line annotation per skipped platform, linking the corresponding job log.

The experience context is the CI engineer reviewing or merging the upgrade PR — they observe that composition and validation happen exactly once, in dedicated jobs, before the PR is composed; they can tell from the PR body which platforms updated this cycle and which carried forward; and they can trust that the version manifest they're reviewing is the same byte-for-byte content the validation gate approved.

#### Scenario: Happy path — both platforms produce fragments

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** `update_android_version` and `update_windows_version` both produced their fragment artifacts
- **WHEN** `compose_version_manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter`, new `android`, and new `windows` blocks
- **AND** `validate_config_version` runs against the composed artifact and exits 0
- **AND** the PR opens with this exact composed manifest as its `config/version.json`
- **AND** the PR body does not include any "toolchain unchanged this cycle" annotations

#### Scenario: Build-tools version tracks the new Flutter tag (preserved)

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at tag `X.Y.Z` lists `build-tools;A.B.C` as the only build-tools entry
- **AND** `update_android_version` produced its fragment artifact
- **WHEN** the PR is created
- **THEN** `config/version.json` in the PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Build-tools picks highest version when packages.txt lists multiple (preserved)

- **GIVEN** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at the target tag contains the line `build-tools;A.B.C,build-tools;D.E.F,build-tools;G.H.I:build-tools` where `A.B.C` is the highest version
- **WHEN** `update_android_version` extracts the build-tools version
- **THEN** the extracted value is `A.B.C` exactly (no trailing `,build-tools` suffix and no other suffix)
- **AND** `config/version.json` in the resulting PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Composed manifest is schema-valid before PR work begins

- **GIVEN** `compose_version_manifest` produced its composed artifact
- **WHEN** `validate_config_version` runs against that artifact
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- **AND** the workflow only proceeds to `update_docs_and_create_pr` if validation passes
- **AND** `update_docs_and_create_pr` does not run `cue vet` again

#### Scenario: Git for Windows tracks the latest published tag (preserved)

- **GIVEN** `https://api.github.com/repos/git-for-windows/git/releases/latest` returns an asset whose underlying Git semver is `M.m.p`
- **AND** `update_windows_version` produced its fragment artifact
- **WHEN** the upgrade PR is created
- **THEN** `config/version.json` in the PR contains `windows.git.version == "M.m.p"`

#### Scenario: Android skipped — carried-forward block

- **GIVEN** `update_android_version` did not produce a fragment this cycle (e.g., Flutter's `packages.txt` unreachable)
- **AND** `update_flutter_version` and `update_windows_version` produced their artifacts
- **WHEN** `compose_version_manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and new `windows` blocks
- **AND** the `android` block in the composed manifest is byte-for-byte identical to the `android` block on the base branch
- **AND** `validate_config_version` exits 0
- **AND** the PR opens with the composed manifest
- **AND** the PR body contains a one-line annotation indicating the Android toolchain was unchanged this cycle, with a link to the `update_android_version` job log

#### Scenario: Windows skipped — carried-forward block (preserved)

- **GIVEN** `update_windows_version` did not produce a fragment this cycle (e.g., release-identity mismatch in Microsoft's upstream)
- **AND** `update_flutter_version` and `update_android_version` produced their artifacts
- **WHEN** `compose_version_manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and new `android` blocks
- **AND** the `windows` block in the composed manifest is byte-for-byte identical to the `windows` block on the base branch
- **AND** `validate_config_version` exits 0
- **AND** the PR opens with the composed manifest
- **AND** the PR body contains a one-line annotation indicating the Windows toolchain was unchanged this cycle, with a link to the `update_windows_version` job log

#### Scenario: Both platforms skipped — Flutter-only PR

- **GIVEN** neither `update_android_version` nor `update_windows_version` produced a fragment this cycle
- **AND** `update_flutter_version` produced its artifact
- **WHEN** `compose_version_manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` block
- **AND** the `android` and `windows` blocks are byte-for-byte identical to the base branch
- **AND** `validate_config_version` exits 0
- **AND** the PR opens with both per-platform "unchanged this cycle" annotations in its body

### Requirement: Producer jobs validate their own `version.json` before upload

Each job in `update_version.yml` that writes a fragment to `config/version.json` and uploads it as an artifact SHALL run `cue vet config/schema.cue -d '#Version' config/version.json` (or `-d '#FlutterVersion'` for the flutter-only artifact) immediately before the upload step and SHALL fail that job on validation error. Producer-side validation runs against the partial manifest the producer has in hand (its own block overlaid onto the base manifest checked out at job start), giving an early failure surface that points at the offending producer rather than at the centralized compose step.

The experience context is the CI engineer triaging a failed scheduled run — they see the failing job pointing at the step that produced the bad data, rather than a downstream `validate_config_version` failure that blames the schema without naming the producer.

#### Scenario: Android producer catches its own bad output

- **GIVEN** the `update_android_version` job writes a fragment whose `android.buildTools.version` does not match `^\d+\.\d+\.\d+$`
- **WHEN** the job's validation step runs before artifact upload
- **THEN** `cue vet` exits non-zero and the `update_android_version` job is marked failed
- **AND** the artifact upload step does not execute
- **AND** the downstream `compose_version_manifest` job tolerates the missing fragment and carries forward the base-branch `android` block (no `version.json` corruption propagates)

#### Scenario: Producer validation passes for a well-formed manifest

- **GIVEN** the `update_android_version` job produces a fragment whose `android` block satisfies `#Version`
- **WHEN** the job's validation step runs
- **THEN** `cue vet` exits 0
- **AND** the artifact upload step runs and uploads the fragment
