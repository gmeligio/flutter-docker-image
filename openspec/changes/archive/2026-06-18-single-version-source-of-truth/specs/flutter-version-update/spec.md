## MODIFIED Requirements

### Requirement: Scheduled run opens an upgrade PR when a new stable Flutter is released

The `update-version.yml` workflow SHALL open exactly one pull request titled `chore(release): upgrade flutter to <version>` whenever the latest entry in `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` matching the stable channel and a `\d+.\d+.\d+` version differs from the version currently pinned in `config/version.json` (`.flutter.version`).

`config/version.json` is the single committed source of truth for the pinned Flutter version; there is no separate `config/flutter_version.json`. The change-detection anchor and the file the PR modifies are the same, so the automation can never delete an anchor a subsequent run depends on.

The experience context is the CI engineer who watches this repository for upgrade PRs to merge into their image fork.

#### Scenario: Upstream ships a new stable Flutter

- **GIVEN** `config/version.json` pins Flutter `X.Y.Z` (`.flutter.version == "X.Y.Z"`)
- **AND** the latest stable release in `releases_linux.json` is `X.Y.Z+1`
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** a branch `update-flutter-dependencies/X.Y.Z+1` is pushed
- **AND** a pull request is opened with title `chore(release): upgrade flutter to X.Y.Z+1`
- **AND** the commit message on that PR equals the title (non-empty)
- **AND** the PR diff does not delete `config/flutter_version.json` (the file does not exist)

#### Scenario: No upstream change since last run

- **GIVEN** `config/version.json` already pins the latest stable Flutter version
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** no branch is created
- **AND** no pull request is opened
- **AND** all jobs after `update-flutter-version` are skipped

### Requirement: Producer jobs validate their own block before emitting it

Each platform-updater job in `update-version.yml` SHALL overlay its block onto its in-job checkout of `config/version.json`, run `cue vet config/schema.cue -d '#Version' config/version.json`, and fail the job on validation error — *before* it emits its block as a job output. Because `config/schema.cue` defines no per-platform definition (only `#WindowsToolchain`, `#FlutterVersion`, and the top-level `#Version`), producer-side validation runs against the *full* manifest the producer has in hand — its own block(s) overlaid onto the schema-valid base checked out at job start — not against an isolated fragment. This gives an early failure surface that points at the offending producer rather than at the downstream composition gate.

Producers report their block as a compact JSON job **output**, not as an uploaded artifact: `update-flutter-version` emits the resolved `flutter` scalars (`flutter_channel`, `flutter_commit`, `flutter_version`); `update-android-version` emits `android_block` (`{android, fastlane}` — both written by that job); `update-windows-version` emits `windows_block` (`{windows}`) when its release-identity check matches, otherwise an empty output. The Flutter producer is not a special case validated against a standalone `#FlutterVersion` file — it validates the full in-job `#Version` manifest like the others.

The experience context is the CI engineer triaging a failed scheduled run — they see the failing job pointing at the step that produced the bad data, rather than a downstream composition failure that blames the schema without naming the producer.

#### Scenario: Android producer catches its own bad output

- **GIVEN** the `update-android-version` job overlays an `android` block whose `android.buildTools.version` does not match `^\d+\.\d+\.\d+$`
- **WHEN** the job's validation step runs before it emits `android_block`
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits non-zero and the `update-android-version` job is marked failed
- **AND** `android_block` is not emitted (empty)
- **AND** the downstream composition tolerates the empty output and carries forward the base-branch `android` block (no corruption propagates)

#### Scenario: Producer validation passes for a well-formed manifest

- **GIVEN** a producer overlays a block that satisfies `#Version`
- **WHEN** the job's validation step runs
- **THEN** `cue vet` exits 0
- **AND** the producer emits its block as a job output

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL be composed and validated in a single `compose-and-open-pr` job before the PR is created. There is no separate `compose-version-manifest` or `validate-config-version` job. The job checks out the schema-valid base manifest, overlays the platform blocks read from the producer jobs' outputs, regenerates `test/android.yml` from the composed manifest, runs the validation gate, and only then opens the PR.

The composed manifest SHALL satisfy `cue vet config/schema.cue -d '#Version' config/version.json` (run as a gating step strictly before any PR-creation step) and SHALL contain:

- the `flutter` block from `update-flutter-version`'s outputs (always overlaid — the pipeline is gated on Flutter having changed),
- the `android` and `fastlane` blocks from `update-android-version`'s `android_block` output *if* that output is non-empty this cycle, otherwise the `android` and `fastlane` blocks as committed on the base branch,
- the `windows` block from `update-windows-version`'s `windows_block` output *if* that output is non-empty this cycle, otherwise the `windows` block as committed on the base branch.

`test/android.yml` SHALL be regenerated by `script/update_test.sh` from the composed `config/version.json` (it is derived from the manifest, not shipped between jobs); on the Android-skip path the carried-forward base `android` block reproduces the base `test/android.yml`. When either platform updater produced no block this cycle, the PR body SHALL include a one-line annotation per skipped platform, linking the corresponding job log.

The experience context is the CI engineer reviewing or merging the upgrade PR — composition and validation happen exactly once, adjacently, before the PR is composed; the reviewer can tell from the PR body which platforms updated and which carried forward, and can trust that the manifest they review is the same content the validation gate approved.

#### Scenario: Happy path — both platforms produce blocks

- **GIVEN** the workflow is opening an upgrade PR for Flutter `X.Y.Z`
- **AND** `update-android-version` and `update-windows-version` both emitted non-empty block outputs
- **WHEN** `compose-and-open-pr` runs
- **THEN** the composed `config/version.json` contains the new `flutter`, `android`, and `windows` blocks
- **AND** the validation gate `cue vet config/schema.cue -d '#Version' config/version.json` exits 0 before the PR step
- **AND** `test/android.yml` is regenerated from the composed manifest
- **AND** the PR opens with this composed manifest and regenerated test file
- **AND** the PR body does not include any "toolchain unchanged this cycle" annotations

#### Scenario: Build-tools version tracks the new Flutter tag (preserved)

- **GIVEN** Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` at tag `X.Y.Z` lists `build-tools;A.B.C` as the only build-tools entry
- **AND** `update-android-version` emitted its block output
- **WHEN** the PR is created
- **THEN** `config/version.json` in the PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Build-tools picks highest version when packages.txt lists multiple (preserved)

- **GIVEN** Flutter's `packages.txt` at the target tag contains `build-tools;A.B.C,build-tools;D.E.F,build-tools;G.H.I:build-tools` where `A.B.C` is the highest
- **WHEN** `update-android-version` extracts the build-tools version
- **THEN** the extracted value is `A.B.C` exactly (no trailing suffix)
- **AND** `config/version.json` in the resulting PR contains `android.buildTools.version == "A.B.C"`

#### Scenario: Composed manifest is schema-valid before PR work begins

- **GIVEN** `compose-and-open-pr` has overlaid the platform blocks onto the base manifest
- **WHEN** the validation gate step runs
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- **AND** the PR-creation step runs only if the gate passed
- **AND** if the gate fails the job fails and no PR is opened

#### Scenario: Git for Windows tracks the latest published tag (preserved)

- **GIVEN** `https://api.github.com/repos/git-for-windows/git/releases/latest` returns an asset whose underlying Git semver is `M.m.p`
- **AND** `update-windows-version` emitted its block output
- **WHEN** the upgrade PR is created
- **THEN** `config/version.json` in the PR contains `windows.git.version == "M.m.p"`

#### Scenario: Android skipped — carried-forward block

- **GIVEN** `update-android-version` emitted no block this cycle (e.g., Flutter's `packages.txt` unreachable)
- **AND** `update-flutter-version` changed and `update-windows-version` emitted its block
- **WHEN** `compose-and-open-pr` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and `windows` blocks
- **AND** the `android` block is byte-for-byte identical to the base branch
- **AND** `test/android.yml` regenerated from the composed manifest is byte-for-byte identical to the base branch
- **AND** the validation gate exits 0 and the PR opens
- **AND** the PR body contains a one-line annotation that the Android toolchain was unchanged this cycle, linking the `update-android-version` job log

#### Scenario: Windows skipped — carried-forward block (preserved)

- **GIVEN** `update-windows-version` emitted no block this cycle (e.g., release-identity mismatch upstream)
- **AND** `update-flutter-version` changed and `update-android-version` emitted its block
- **WHEN** `compose-and-open-pr` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and `android` blocks
- **AND** the `windows` block is byte-for-byte identical to the base branch
- **AND** the validation gate exits 0 and the PR opens
- **AND** the PR body contains a one-line annotation that the Windows toolchain was unchanged this cycle, linking the `update-windows-version` job log

#### Scenario: Both platforms skipped — Flutter-only PR

- **GIVEN** neither `update-android-version` nor `update-windows-version` emitted a block this cycle
- **AND** `update-flutter-version` changed
- **WHEN** `compose-and-open-pr` runs
- **THEN** the composed `config/version.json` contains the new `flutter` block
- **AND** the `android` and `windows` blocks are byte-for-byte identical to the base branch
- **AND** the validation gate exits 0 and the PR opens with both per-platform "unchanged this cycle" annotations

### Requirement: Schema rejects non-stable Flutter channels

`config/schema.cue` SHALL constrain `flutter.channel` to the literal `"stable"` via `#FlutterVersion`, which is embedded in `#Version`. Any `config/version.json` whose `flutter.channel` is anything else SHALL fail `cue vet config/schema.cue -d '#Version' config/version.json`.

The experience context is the CI engineer running schema validation locally (or via the `build.yml` `validate-version-files` step) — they get an immediate, loud failure if a non-stable release leaks into the manifest.

#### Scenario: Non-stable channel fails validation

- **GIVEN** a `config/version.json` with `flutter.channel == "beta"`
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits non-zero with a constraint-violation error on `flutter.channel`

#### Scenario: Committed manifest is schema-valid and the schema is well-formed

- **GIVEN** the current `config/schema.cue` and committed `config/version.json`
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits 0
- **AND** no undefined-reference error (e.g. `reference "#PatchVersion" not found`) is produced
