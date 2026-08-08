## MODIFIED Requirements

### Requirement: Android producer derives the installed Java major version

The `update-android-version` job SHALL derive the Java major version from the
**pinned Flutter checkout** — the `errorJavaVersion` constant on
`com.flutter.gradle.DependencyVersionChecker`, as compiled from the Flutter tag
being built — and write it into `config/version.json` at `android.java.version` as
a positive integer, before it emits `android_block`. The derivation SHALL NOT read
the JDK installed in the running container: that value describes the previously
published image and cannot determine what the next image should install.

The derivation SHALL read the **compiled constant** from the Flutter Gradle plugin
on the task's classpath, not the source text of the file that declares it. The
plugin is on that classpath because the generated app's `settings.gradle.kts` does
`includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`, making it a
composite included build compiled at the pinned tag. Since Kotlin's `internal`
compiles to a `public` JVM getter with a `$<module-name>` suffix, the value is
reachable by ordinary reflection without `setAccessible`. The lookup SHALL match
the getter by name prefix rather than hardcoding the mangled suffix, so that a
rename of the upstream Gradle module does not break it, and SHALL use
`JavaVersion.majorVersion` rather than `toString()`, which diverge for Java 8
(`"8"` vs `"1.8"`).

The derivation SHALL live in `script/updateAndroidVersions.gradle.kts` alongside
the other four Android values that task already derives (`platforms`, `gradle`,
`buildTools`, `ndk`), rather than in a separate workflow step.

`errorJavaVersion` is Flutter's enforced floor — the version below which
`checkJavaVersion` fails the build. It is the only Java version Flutter defines:
`gradle_utils.dart` publishes `maxKnownAndSupported*` constants for Gradle, KGP and
AGP, but none for Java, and `oneMajorVersionHigherJavaVersion` is derived from the
maximum supported Gradle rather than from a Java policy. The
`flutter create` template's `compileOptions.sourceCompatibility` SHALL NOT be used
as the source: it declares a bytecode target rather than a JDK requirement, and it
lives in a generated file that application authors are invited to edit.

Because `android.java` lives in the `android` block, the emitted `android_block`
(`{android, fastlane}`) SHALL include it, and on an Android-skip cycle the
base-branch `android.java` SHALL carry forward unchanged with the rest of the
`android` block. A derivation that resolves no getter — because upstream renamed
or removed the constant — SHALL fail the task rather than emit a stale or empty
value, and the failure message SHALL list the members it did find, so the upstream
change is diagnosable from the job log alone.

The regenerated `test/android.yml` SHALL include a structure-test assertion that
the built `flutter-android` image's `java -version` major equals
`android.java.version`, templated from the manifest via `config/android.cue` (the
`android_java_version` tag) and `script/update_test.sh`. This makes the manifest ↔
image agreement machine-checked at build time, so a Dockerfile JDK-major change not
reflected in `config/version.json` fails the `build.yml` test leg.

The experience context is the CI engineer who needs the image's JDK to track what
Flutter actually requires, on Flutter's release cadence, without a maintainer
deciding the number each cycle.

**What this replaces, and why.** The prior derivation ran `script/java_version.sh`
(`java -version`) inside the *previously published* container, so
`android.java.version` described the last build rather than determining the next
one, and lagged one release cycle by construction. It could not influence what the
image installed — the JDK was fixed by hand-typed strings in `android.Dockerfile`
— making the field a mirror labelled as a dial. `script/java_version.sh` and the
`Derive installed Java major version` step (`update-version.yml:296-303`) are
deleted; because the derivation moves into the Gradle task that already writes the
other four Android values, no replacement workflow step is added.

No consumer changes: `config/schema.cue`, `config/android.cue`,
`script/update_test.sh` and `test/android.yml` all continue to read
`android.java.version` unchanged, and the separate requirement *"Schema requires
the Android Java major version"* is unaffected — the field's name, type and
required-ness are identical. The committed manifest value does not change (both
the old and new sources yield `17`), so the migration produces no diff in
`config/version.json`.

#### Scenario: Java major is derived from the pinned Flutter checkout and emitted

- **GIVEN** the pinned Flutter checkout declares `errorJavaVersion = JavaVersion.VERSION_N`
- **WHEN** `update-android-version` runs
- **THEN** `config/version.json` gets `android.java.version == N` (an integer)
- **AND** the emitted `android_block` contains `android.java`
- **AND** the producer's `cue vet config/schema.cue -d '#Version' config/version.json` step exits 0
- **AND** the job log records the derived value, that it came from `errorJavaVersion`, and the mangled getter name that was resolved

#### Scenario: Derivation reads the compiled constant, not the source text

- **GIVEN** the Flutter Gradle plugin is on the task's classpath as a composite included build
- **WHEN** the derivation resolves `errorJavaVersion`
- **THEN** it reflects over `com.flutter.gradle.DependencyVersionChecker`
- **AND** it does not read the text of `DependencyVersionChecker.kt`
- **AND** it succeeds without calling `setAccessible`, requiring no JVM `--add-opens`

#### Scenario: Upstream Gradle module rename does not break the lookup

- **GIVEN** the compiled getter is mangled as `getErrorJavaVersion$<module>` for any module name
- **WHEN** the derivation resolves the getter by name prefix
- **THEN** it matches regardless of the suffix
- **AND** it also matches an unmangled `getErrorJavaVersion`

#### Scenario: Derivation is independent of the container's installed JDK

- **GIVEN** the `flutter-android` container has OpenJDK major `M` installed
- **AND** the pinned Flutter checkout declares `errorJavaVersion` major `N` where `N != M`
- **WHEN** `update-android-version` runs
- **THEN** `config/version.json` gets `android.java.version == N`
- **AND** the value of `M` does not influence the result

#### Scenario: Upstream constant renamed or removed fails the producer, base value carried forward

- **GIVEN** the pinned Flutter checkout's `DependencyVersionChecker` exposes no `errorJavaVersion` getter
- **WHEN** the derivation runs
- **THEN** the `updateAndroidVersions` task fails and `update-android-version` is marked failed
- **AND** the failure message lists the members that were found
- **AND** `android_block` is not emitted (empty)
- **AND** `compose-and-open-pr` carries forward the base-branch `android` block (including `android.java`) unchanged

#### Scenario: Bad Java derivation fails the producer, base value carried forward

- **GIVEN** the derivation yields a value that is not a positive integer
- **WHEN** the producer's validation step runs before it emits `android_block`
- **THEN** `cue vet config/schema.cue -d '#Version' config/version.json` exits non-zero and `update-android-version` is marked failed
- **AND** `android_block` is not emitted (empty)
- **AND** `compose-and-open-pr` carries forward the base-branch `android` block (including `android.java`) unchanged

#### Scenario: Android skipped — Java carried forward

- **GIVEN** `update-android-version` emitted no block this cycle
- **WHEN** `compose-and-open-pr` runs
- **THEN** `android.java` in the composed `config/version.json` is byte-for-byte identical to the base branch

#### Scenario: Built image's Java major is asserted against the manifest

- **GIVEN** `config/version.json` has `android.java.version == N`
- **AND** `test/android.yml` has been regenerated by `script/update_test.sh`
- **WHEN** `container-structure-test` runs against the built `flutter-android` image in `build.yml`
- **THEN** the "Java is pinned" test asserts the image's `java -version` major equals `N`
- **AND** a built image whose JDK major differs from `N` turns the test (and the PR check) red

#### Scenario: Manifest change flows into the regenerated test

- **GIVEN** `android.java.version` is changed from `N` to `M` in `config/version.json`
- **WHEN** `script/update_test.sh` regenerates `test/android.yml`
- **THEN** the "Java is pinned" assertion's `expectedOutput` becomes `M`
- **AND** re-running `script/update_test.sh` produces no further change (the file is a fixed point)

## ADDED Requirements

### Requirement: The image's JDK major follows the manifest, not a hand-typed string

`android.Dockerfile` SHALL derive both `JAVA_HOME` and the installed JDK package
name from a single build argument carrying the manifest's
`android.java.version`. Neither the JDK major in `JAVA_HOME` nor the major in the
`openjdk-<major>-jdk-headless` package name SHALL be written as a literal.

The apt *patch* pin (`OPENJDK_17_JDK_HEADLESS_VERSION`) remains Renovate-managed
and is unaffected: the manifest owns the major, Renovate owns the patch.

**Experience context:** A CI engineer pulling the image gets a JDK whose version
matches what the manifest and README report. Before this requirement, the shipped
JDK was fixed by two hand-typed strings that nothing checked, while
`config/version.json` merely reported what a prior build happened to contain — so
the manifest could disagree with the image indefinitely and silently.

#### Scenario: JAVA_HOME follows the manifest

- **GIVEN** `config/version.json` has `android.java.version == N`
- **WHEN** the `flutter-android` image is built
- **THEN** the image's `JAVA_HOME` resolves to the OpenJDK `N` installation directory
- **AND** `android.Dockerfile` contains no literal JDK major in its `JAVA_HOME` assignment

#### Scenario: Installed package follows the manifest

- **GIVEN** `config/version.json` has `android.java.version == N`
- **WHEN** the image build installs the JDK
- **THEN** the package installed is `openjdk-N-jdk-headless`
- **AND** its version is the Renovate-managed patch pin

#### Scenario: Manifest and image cannot silently disagree

- **GIVEN** a change that would make the installed JDK major differ from `android.java.version`
- **WHEN** the `build.yml` test leg runs `container-structure-test`
- **THEN** the "Java is pinned" assertion fails and the PR check turns red

### Requirement: The Gradle task asserts the installed JDK meets Flutter's floor

`script/updateAndroidVersions.gradle.kts` SHALL assert that the JDK running Gradle
is at least Flutter's enforced floor, failing the task otherwise. The assertion
SHALL compare against the value derived in that same task, not a restated literal,
so the floor cannot drift from the derived version.

**Experience context:** On the cycle where Flutter raises its floor, the task runs
inside the *previously published* image, whose JDK is one major behind the value
just derived. A CI engineer who would otherwise hit a failure deep inside Flutter's
own dependency check instead gets an immediate, named failure at the point the
toolchain is interrogated. This is an assertion, not a derivation — reading the
running JDK to *decide* the version would be circular, but reading it to *check* a
floor is sound.

The scope is deliberately narrow: in steady state the container's JDK and the
derived value both come from the same manifest field, so the assertion compares a
value against itself and cannot fire. It guards the lag window on a floor bump,
not the installed JDK generally.

#### Scenario: Flutter raises its floor above the running container's JDK

- **GIVEN** the previously published image installed JDK major `M`
- **AND** the pinned Flutter checkout now enforces `errorJavaVersion` major `N` where `N > M`
- **WHEN** the `updateAndroidVersions` task runs inside that image
- **THEN** the task fails with a message naming `N` as the required minimum
- **AND** the failure occurs before `config/version.json` is written

#### Scenario: JDK at or above the floor proceeds

- **GIVEN** the container's JDK major is at or above Flutter's `errorJavaVersion`
- **WHEN** the `updateAndroidVersions` task runs
- **THEN** the assertion passes and the task writes the manifest as normal
- **AND** in steady state this is the case, because both values derive from the same manifest field

