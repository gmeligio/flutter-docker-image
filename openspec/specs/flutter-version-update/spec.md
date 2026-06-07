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

When the workflow opens an upgrade PR, the included `config/version.json` SHALL be a single composed manifest produced by the `compose-version-manifest` job and validated by `validate-config-version` before any PR work begins. The composed manifest SHALL satisfy `cue vet config/schema.cue -d '#Version'` and SHALL contain:

- the `flutter` block written by `update-flutter-version` (always present — the pipeline is gated on Flutter having changed),
- the `android` and `fastlane` blocks written by `update-android-version` *if* that job produced its fragment artifact this cycle, otherwise the `android` and `fastlane` blocks as committed on the base branch (both ride the Android fragment because both are written by that job),
- the `windows` block written by `update-windows-version` *if* that job produced its fragment artifact this cycle, otherwise the `windows` block as committed on the base branch.

The job that creates the pull request (`update-docs-and-create-pr`) SHALL be a read-only consumer of the composed and validated manifest: it SHALL NOT run `jq` against `config/version.json`, SHALL NOT re-validate it, and SHALL NOT depend on the individual platform-updater jobs' artifacts.

When either platform updater skipped its update this cycle, the PR body SHALL include a one-line annotation per skipped platform, linking the corresponding job log.

The experience context is the CI engineer reviewing or merging the upgrade PR — they observe that composition and validation happen exactly once, in dedicated jobs, before the PR is composed; they can tell from the PR body which platforms updated this cycle and which carried forward; and they can trust that the version manifest they're reviewing is the same byte-for-byte content the validation gate approved.

#### Scenario: Happy path — both platforms produce fragments

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** `update-android-version` and `update-windows-version` both produced their fragment artifacts
- **WHEN** `compose-version-manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter`, new `android`, and new `windows` blocks
- **AND** `validate-config-version` runs against the composed artifact and exits 0
- **AND** the PR opens with this exact composed manifest as its `config/version.json`
- **AND** the PR body does not include any "toolchain unchanged this cycle" annotations

#### Scenario: Build-tools version tracks the new Flutter tag (preserved)

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at tag `X.Y.Z` lists `build-tools;A.B.C` as the only build-tools entry
- **AND** `update-android-version` produced its fragment artifact
- **WHEN** the PR is created
- **THEN** `config/version.json` in the PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Build-tools picks highest version when packages.txt lists multiple (preserved)

- **GIVEN** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at the target tag contains the line `build-tools;A.B.C,build-tools;D.E.F,build-tools;G.H.I:build-tools` where `A.B.C` is the highest version
- **WHEN** `update-android-version` extracts the build-tools version
- **THEN** the extracted value is `A.B.C` exactly (no trailing `,build-tools` suffix and no other suffix)
- **AND** `config/version.json` in the resulting PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Composed manifest is schema-valid before PR work begins

- **GIVEN** `compose-version-manifest` produced its composed artifact
- **WHEN** `validate-config-version` runs against that artifact
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- **AND** the workflow only proceeds to `update-docs-and-create-pr` if validation passes
- **AND** `update-docs-and-create-pr` does not run `cue vet` again

#### Scenario: Git for Windows tracks the latest published tag (preserved)

- **GIVEN** `https://api.github.com/repos/git-for-windows/git/releases/latest` returns an asset whose underlying Git semver is `M.m.p`
- **AND** `update-windows-version` produced its fragment artifact
- **WHEN** the upgrade PR is created
- **THEN** `config/version.json` in the PR contains `windows.git.version == "M.m.p"`

#### Scenario: Android skipped — carried-forward block

- **GIVEN** `update-android-version` did not produce a fragment this cycle (e.g., Flutter's `packages.txt` unreachable)
- **AND** `update-flutter-version` and `update-windows-version` produced their artifacts
- **WHEN** `compose-version-manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and new `windows` blocks
- **AND** the `android` block in the composed manifest is byte-for-byte identical to the `android` block on the base branch
- **AND** `validate-config-version` exits 0
- **AND** the PR opens with the composed manifest
- **AND** the PR body contains a one-line annotation indicating the Android toolchain was unchanged this cycle, with a link to the `update-android-version` job log

#### Scenario: Windows skipped — carried-forward block (preserved)

- **GIVEN** `update-windows-version` did not produce a fragment this cycle (e.g., release-identity mismatch in Microsoft's upstream)
- **AND** `update-flutter-version` and `update-android-version` produced their artifacts
- **WHEN** `compose-version-manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and new `android` blocks
- **AND** the `windows` block in the composed manifest is byte-for-byte identical to the `windows` block on the base branch
- **AND** `validate-config-version` exits 0
- **AND** the PR opens with the composed manifest
- **AND** the PR body contains a one-line annotation indicating the Windows toolchain was unchanged this cycle, with a link to the `update-windows-version` job log

#### Scenario: Both platforms skipped — Flutter-only PR

- **GIVEN** neither `update-android-version` nor `update-windows-version` produced a fragment this cycle
- **AND** `update-flutter-version` produced its artifact
- **WHEN** `compose-version-manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` block
- **AND** the `android` and `windows` blocks are byte-for-byte identical to the base branch
- **AND** `validate-config-version` exits 0
- **AND** the PR opens with both per-platform "unchanged this cycle" annotations in its body

### Requirement: Producer jobs validate their own `version.json` before upload

Each job in `update-version.yml` that writes a fragment to `config/version.json` and uploads it as an artifact SHALL run `cue vet config/schema.cue -d '#Version' config/version.json` (or `-d '#FlutterVersion'` for the flutter-only artifact) immediately before the upload step and SHALL fail that job on validation error. Because `config/schema.cue` defines no per-platform definition (only `#WindowsToolchain`, `#FlutterVersion`, and the top-level `#Version`), producer-side validation runs against the *full* manifest the producer has in hand — its own block(s) overlaid onto the base manifest checked out at job start — not against the extracted fragment. This gives an early failure surface that points at the offending producer rather than at the centralized compose step. The Android producer's blocks are `android` and `fastlane` (both written by `update-android-version`); the Windows producer's block is `windows`.

The experience context is the CI engineer triaging a failed scheduled run — they see the failing job pointing at the step that produced the bad data, rather than a downstream `validate-config-version` failure that blames the schema without naming the producer.

#### Scenario: Android producer catches its own bad output

- **GIVEN** the `update-android-version` job writes a fragment whose `android.buildTools.version` does not match `^\d+\.\d+\.\d+$`
- **WHEN** the job's validation step runs before artifact upload
- **THEN** `cue vet` exits non-zero and the `update-android-version` job is marked failed
- **AND** the artifact upload step does not execute
- **AND** the downstream `compose-version-manifest` job tolerates the missing fragment and carries forward the base-branch `android` block (no `version.json` corruption propagates)

#### Scenario: Producer validation passes for a well-formed manifest

- **GIVEN** the `update-android-version` job produces a fragment whose `android` block satisfies `#Version`
- **WHEN** the job's validation step runs
- **THEN** `cue vet` exits 0
- **AND** the artifact upload step runs and uploads the fragment

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

