# flutter-version-update Specification

## Requirements

### Requirement: Scheduled run opens an upgrade PR when a new stable Flutter is released

The `update_version.yml` workflow SHALL open exactly one pull request titled `chore(release): upgrade flutter to <version>` whenever the latest entry in `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` matching the stable channel and a `\d+.\d+.\d+` version differs from the version currently pinned in `config/flutter_version.json`.

The experience context is the CI engineer who watches this repository for upgrade PRs to merge into their image fork.

#### Scenario: Upstream ships a new stable Flutter

- **GIVEN** `config/flutter_version.json` pins Flutter `X.Y.Z`
- **AND** the latest stable release in `releases_linux.json` is `X.Y.Z+1`
- **WHEN** the scheduled run of `update_version.yml` executes
- **THEN** a branch `update-flutter-dependencies/X.Y.Z+1` is pushed
- **AND** a pull request is opened with title `chore(release): upgrade flutter to X.Y.Z+1`
- **AND** the commit message on that PR equals the title (non-empty)

#### Scenario: No upstream change since last run

- **GIVEN** `config/flutter_version.json` already pins the latest stable Flutter version
- **WHEN** the scheduled run of `update_version.yml` executes
- **THEN** no branch is created
- **AND** no pull request is opened
- **AND** all jobs after `update_flutter_version` are skipped

### Requirement: Upgrade PR contains a coherent, validated `version.json`

When the workflow opens an upgrade PR, the included `config/version.json` SHALL satisfy `cue vet config/schema.cue -d '#Version'` and SHALL contain the Android `buildTools.version` listed for that exact Flutter tag in `engine/src/flutter/tools/android_sdk/packages.txt` upstream.

The experience context is the CI engineer reviewing or merging the upgrade PR — they observe that downstream image builds will not silently regress on Android tooling.

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
