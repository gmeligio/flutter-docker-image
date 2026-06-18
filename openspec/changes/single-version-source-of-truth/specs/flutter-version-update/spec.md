## MODIFIED Requirements

### Requirement: Scheduled run opens an upgrade PR when a new stable Flutter is released

The `update-version.yml` workflow SHALL open exactly one pull request titled `chore(release): upgrade flutter to <version>` whenever the latest entry in `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` matching the stable channel and a `\d+.\d+.\d+` version differs from the version currently pinned in `config/version.json` (`.flutter.version`).

`config/version.json` is the single committed source of truth for the pinned Flutter version; there is no separate `config/flutter_version.json`. The change-detection anchor and the data that becomes the PR are the same file, so the automation can never delete the anchor a subsequent run depends on.

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

### Requirement: Producer jobs validate their own `version.json` before upload

Each job in `update-version.yml` that writes a block to `config/version.json` and uploads it as a fragment artifact SHALL run `cue vet config/schema.cue -d '#Version' config/version.json` immediately before the upload step and SHALL fail that job on validation error. Because `config/schema.cue` defines no per-platform definition (only `#WindowsToolchain`, `#FlutterVersion`, and the top-level `#Version`), producer-side validation runs against the *full* manifest the producer has in hand — its own block(s) overlaid onto the base manifest checked out at job start — not against the extracted fragment. This gives an early failure surface that points at the offending producer rather than at the centralized compose step.

All three producers are symmetric fragment producers: `update-flutter-version` writes the `flutter` block and uploads `version.json.flutter`; `update-android-version` writes the `android` and `fastlane` blocks and uploads `version.json.android`; `update-windows-version` writes the `windows` block and uploads `version.json.windows`. The Flutter producer is no longer a special case validated against a standalone `#FlutterVersion` file — it validates the full in-job `#Version` manifest like the others. `#FlutterVersion` remains a building block embedded in `#Version`.

The experience context is the CI engineer triaging a failed scheduled run — they see the failing job pointing at the step that produced the bad data, rather than a downstream `validate-config-version` failure that blames the schema without naming the producer.

#### Scenario: Flutter producer catches its own bad output

- **GIVEN** the `update-flutter-version` job overlays a `flutter` block whose `channel` is not `"stable"`
- **WHEN** the job's validation step runs before fragment upload
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits non-zero and the `update-flutter-version` job is marked failed
- **AND** the `version.json.flutter` fragment is not uploaded
- **AND** no upgrade PR is opened (the pipeline is gated on the Flutter producer succeeding)

#### Scenario: Android producer catches its own bad output

- **GIVEN** the `update-android-version` job writes a fragment whose `android.buildTools.version` does not match `^\d+\.\d+\.\d+$`
- **WHEN** the job's validation step runs before artifact upload
- **THEN** `cue vet` exits non-zero and the `update-android-version` job is marked failed
- **AND** the artifact upload step does not execute
- **AND** the downstream `compose-version-manifest` job tolerates the missing fragment and carries forward the base-branch `android` block (no `version.json` corruption propagates)

#### Scenario: Producer validation passes for a well-formed manifest

- **GIVEN** a producer job overlays a block that satisfies `#Version`
- **WHEN** the job's validation step runs
- **THEN** `cue vet` exits 0
- **AND** the producer's fragment upload step runs and uploads the fragment

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
