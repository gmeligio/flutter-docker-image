## ADDED Requirements

### Requirement: Android producer derives the installed Java major version

The `update-android-version` job SHALL derive the Java major version from the running `flutter-android` container (via `script/java_version.sh`) and write it into `config/version.json` at `android.java.version` as a positive integer, before it emits `android_block`. Because `android.java` lives in the `android` block, the emitted `android_block` (`{android, fastlane}`) SHALL include it, and on an Android-skip cycle the base-branch `android.java` SHALL carry forward unchanged with the rest of the `android` block. The derived value mirrors the JDK actually installed by `android.Dockerfile`; it is not a second, hand-maintained pin of the Java major.

The experience context is the CI engineer reading the README's Java version, who needs it to equal the JDK the image actually ships.

#### Scenario: Java major is derived and emitted

- **GIVEN** the `flutter-android` container has OpenJDK major `N` installed
- **WHEN** `update-android-version` runs
- **THEN** `config/version.json` gets `android.java.version == N` (an integer)
- **AND** the emitted `android_block` contains `android.java`
- **AND** the producer's `cue vet config/schema.cue -d '#Version' config/version.json` step exits 0

#### Scenario: Bad Java derivation fails the producer, base value carried forward

- **GIVEN** `script/java_version.sh` yields a value that is not a positive integer
- **WHEN** the producer's validation step runs before it emits `android_block`
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits non-zero and `update-android-version` is marked failed
- **AND** `android_block` is not emitted (empty)
- **AND** `compose-and-open-pr` carries forward the base-branch `android` block (including `android.java`) unchanged

#### Scenario: Android skipped — Java carried forward

- **GIVEN** `update-android-version` emitted no block this cycle
- **WHEN** `compose-and-open-pr` runs
- **THEN** `android.java` in the composed `config/version.json` is byte-for-byte identical to the base branch

### Requirement: Schema requires the Android Java major version

`config/schema.cue` SHALL require `android.java.version` as a positive integer within `#Version`. A `config/version.json` that is missing `android.java`, or whose `android.java.version` is not an integer, SHALL fail `cue vet config/schema.cue -d '#Version' config/version.json`.

The experience context is the CI engineer running the schema gate locally or via the `build.yml` version-file validation — a malformed or missing Java field fails loudly rather than reaching a PR.

#### Scenario: Missing Java field fails validation

- **GIVEN** a `config/version.json` with no `android.java`
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits non-zero on the missing required field

#### Scenario: Committed manifest with Java is schema-valid

- **GIVEN** the committed `config/version.json` with `android.java.version` as an integer
- **WHEN** `cue vet config/schema.cue -d '#Version' config/version.json` runs
- **THEN** the command exits 0
