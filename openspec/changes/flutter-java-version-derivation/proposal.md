## Why

`config/version.json`'s `android.java.version` is derived **backwards**: the
`update-android-version` job runs `script/java_version.sh` *inside the previously
published image* to learn what Java the *next* one should have. It describes the
last build, lags one cycle by construction, and cannot influence what gets
installed — the actual JDK is fixed by two hand-typed strings in
`android.Dockerfile` (`JAVA_HOME` at `:140` and the `openjdk-17-…` package name at
`:164`), neither of which anything checks. It is a mirror labelled as a dial.

Wiring a real value through exposed a second problem: adding **any** field to the
manifest costs five file edits, because `script/setEnvironmentVariables.js`
hand-lists every export and the build-args block is copy-pasted four times. That
cost is why Java was left as a special case in the first place.

Relevance gate: this changes observable behaviour a CI engineer depends on — which
JDK the published image ships, and how it is kept in step with Flutter. Two
existing requirements mandate the current backwards derivation by name, so they
cannot be changed silently.

## What Changes

- **BREAKING**: `android.java.version` is derived from Flutter's enforced floor
  (`errorJavaVersion` in the pinned `DependencyVersionChecker.kt`) instead of from
  the previously-published image. Replaces the requirement at
  `flutter-version-update` that mandates `script/java_version.sh`.
- **BREAKING**: `script/java_version.sh` and the `Derive installed Java major
  version` step (`update-version.yml:296-303`) are deleted.
- `android.Dockerfile` gains `ARG android_java_version`; `JAVA_HOME` and the apt
  package name are both interpolated from it, so the two hand-typed Java strings
  disappear. The apt *patch* pin stays owned by Renovate.
- `script/setEnvironmentVariables.js` derives ARG names mechanically from the
  manifest and emits the whole build-args block as one value; the four copy-pasted
  blocks (`build.yml:158-164`, `build.yml:180-186`, `ci.yml:84-90`,
  `release.yml:112-118`) collapse to `build-args: ${{ env.BUILD_ARGS }}`.
- `script/updateAndroidVersions.gradle.kts` gains a floor assertion —
  `check(JavaVersion.current() >= JavaVersion.VERSION_17)` — failing the build if
  the installed JDK ever drops below what Flutter enforces.

Not in scope, and stated so it is not mistaken for an omission: the Renovate
`mode: full` and PR #531 work (Track A in
`../loud-deb-pin-resolution/research.md`), the nine dead scripts, the
`cmdlineTools` mirror, and the dead `30.0.3` job-env lines.

## Capabilities

### New Capabilities

- `manifest-build-arg-wiring`: `config/version.json` fields reach the Docker build
  as build-args by mechanical name derivation, declared once rather than restated
  per workflow. Covers the naming contract, the single emission point, and the
  per-ARG granularity that keeps layer caching intact.

### Modified Capabilities

- `flutter-version-update`: the requirement *"Android producer derives the
  installed Java major version"* currently mandates deriving from the running
  container via `script/java_version.sh`. It is replaced by derivation from
  Flutter's `errorJavaVersion` floor in the pinned checkout. The
  `test/android.yml` assertion, the schema requirement, and the carry-forward
  behaviour on an Android-skip cycle all survive unchanged.
- `linux-image-package-pinning`: the requirement *"Self-pinned image version
  values are declared with `ARG`, never `ENV`"* needs to accommodate `JAVA_HOME`
  being an `ENV` **interpolated from** an `ARG` — the value is still ARG-declared,
  but it is consumed by an ENV, which the current wording does not anticipate.

## Impact

**Deleted**: `script/java_version.sh`; `update-version.yml:296-303`.

**Modified**: `android.Dockerfile` (`ARG` added above the `ENV` block at
`:139-140`; `JAVA_HOME` and the apt package name interpolated);
`script/setEnvironmentVariables.js` (mechanical derivation + `BUILD_ARGS`);
`script/updateAndroidVersions.gradle.kts` (floor assertion);
`.github/workflows/update-version.yml` (Java derived from the pinned checkout);
`build.yml`, `ci.yml`, `release.yml` (build-args blocks collapse).

**Unchanged by design**: `config/schema.cue` (`android.java` is already
`#PlatformVersion`, an int — all sources satisfy it); `config/android.cue` and
`script/update_test.sh` (already read `android.java.version`, so
`test/android.yml:34-40` keeps asserting correctly and becomes the runtime
confirmation); the nine Renovate-owned apt pins.

**Risk**: `errorJavaVersion` is `internal` + `@VisibleForTesting` and
`checkDependencyVersions()` returns `Unit`, so there is no API to call — this is a
text parse of the pinned Flutter checkout, matching the upstream-parsing pattern
`update-version.yml` already runs for the Windows vsman. It fails loudly on an
upstream file move (empty match → failed step) rather than silently returning a
stale value.
