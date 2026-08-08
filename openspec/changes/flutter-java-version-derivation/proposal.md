## Why

`config/version.json`'s `android.java.version` is derived **backwards**: the
`update-android-version` job runs `script/java_version.sh` *inside the previously
published image* to learn what Java the *next* one should have. It describes the
last build, lags one cycle by construction, and cannot influence what gets
installed — the actual JDK is fixed by two hand-typed strings in
`android.Dockerfile` (`JAVA_HOME` at `:140` and the `openjdk-17-…` package name at
`:164`), neither of which anything checks. It is a mirror labelled as a dial.

Wiring a real value through exposed a second problem — adding any field to the
manifest costs five file edits — but that is a separate concern with its own
user impact, and it is now the change `manifest-build-arg-wiring`. This change
declares `ARG android_java_version` and passes it the way the build passes
arguments today; if the wiring change lands first, that is one table row instead
of four inline edits. Neither blocks the other.

Relevance gate: this changes observable behaviour a CI engineer depends on — which
JDK the published image ships, and how it is kept in step with Flutter. Two
existing requirements mandate the current backwards derivation by name, so they
cannot be changed silently.

## What Changes

- **BREAKING**: `android.java.version` is derived from Flutter's enforced floor
  (`errorJavaVersion` on `com.flutter.gradle.DependencyVersionChecker`, read
  reflectively from the plugin compiled at the pinned tag) instead of from the
  previously-published image. Replaces the requirement at `flutter-version-update`
  that mandates `script/java_version.sh`.
- **BREAKING**: `script/java_version.sh` and the `Derive installed Java major
  version` step (`update-version.yml:296-303`) are deleted. The derivation moves
  into `script/updateAndroidVersions.gradle.kts`, joining the four Android values
  that task already derives (`platforms`, `gradle`, `buildTools`, `ndk`) — so a
  workflow step is removed rather than rewritten.
- `android.Dockerfile` gains `ARG android_java_version`; `JAVA_HOME` and the apt
  package name are both interpolated from it, so the two hand-typed Java strings
  disappear. The apt *patch* pin stays owned by Renovate.
- `script/updateAndroidVersions.gradle.kts` gains a floor assertion —
  `check(JavaVersion.current().majorVersion.toInt() >= javaMajor)` — comparing
  against the value derived in that same task, so there is no second literal to
  drift. Narrow by construction: the task runs inside the previously published
  image, so the assertion fires only on the cycle where Flutter raises its floor
  above the JDK that image shipped, converting a confusing downstream failure into
  a named one.

Not in scope, and stated so it is not mistaken for an omission: the build-argument
wiring refactor (split out as `manifest-build-arg-wiring`), the Renovate
`mode: full` and PR #531 work (Track A in
`../loud-deb-pin-resolution/research.md`), the nine dead scripts, the
`cmdlineTools` mirror, and the dead `30.0.3` job-env lines.

## Capabilities

### Modified Capabilities

- `flutter-version-update`: the requirement *"Android producer derives the
  installed Java major version"* currently mandates deriving from the running
  container via `script/java_version.sh`. It is replaced by reflective derivation
  from Flutter's `errorJavaVersion` floor on the plugin compiled at the pinned
  tag. The `test/android.yml` assertion, the schema requirement, and the
  carry-forward behaviour on an Android-skip cycle all survive unchanged — a
  reflection failure is simply another empty-block cycle, which the existing
  design already handles.
- `linux-image-package-pinning`: the requirement *"Self-pinned image version
  values are declared with `ARG`, never `ENV`"* needs to accommodate `JAVA_HOME`
  being an `ENV` **interpolated from** an `ARG` — the value is still ARG-declared,
  but it is consumed by an ENV, which the current wording does not anticipate.
  The exemption is narrow and stated as a rule, not as a special case for this
  one variable: an `ENV` may embed an `ARG` value when the `ENV` is a **runtime
  path or setting the image must expose**, and the `ARG` it embeds is not itself
  a package pin. `JAVA_HOME` qualifies — it must be in the environment for Gradle
  to find the JDK, and `android_java_version` is a major, not a version pin. The
  nine `*_VERSION` apt pins do not qualify and stay ARG-only, unchanged; they are
  pins, and leaking them into `Env` is what the original requirement forbids.

## Impact

**Deleted**: `script/java_version.sh`; `update-version.yml:296-303`.

**Modified**: `android.Dockerfile` (`ARG` moved above the `ENV` block at
`:139-140`; `JAVA_HOME` and the apt package name interpolated; the three
`moby/moby#29110` TODOs at `:136-138` replaced by a one-line note — see Impact
note below); `script/updateAndroidVersions.gradle.kts` (reflective Java
derivation + floor assertion); `.github/workflows/update-version.yml` (derivation
step removed, not replaced).

**Wiring the value to the build** costs the five edits this repository charges for
any manifest field, and this proposal counts all five rather than eliding them:
one `core.exportVariable('ANDROID_JAVA_VERSION', …)` in
`script/setEnvironmentVariables.js`, plus one `--build-arg` line in each of the
four blocks (`build.yml:158-164`, `build.yml:180-186`, `ci.yml:84-90`,
`release.yml:114-120`). If `manifest-build-arg-wiring` lands first, all five
collapse to one table row. Either way, `android.Dockerfile` declares the `ARG`.

**Comment-only edit, stated for scope completeness**: the three
`moby/moby#29110` TODOs are replaced rather than deleted, because they ask for
*runtime* discovery that moby still blocks. Deleting them silently would read as a
claim that runtime discovery now works. No behaviour change.

**Unchanged by design**: `config/schema.cue` (`android.java` is already
`#PlatformVersion`, an int — all sources satisfy it); `config/android.cue` and
`script/update_test.sh` (already read `android.java.version`, so
`test/android.yml:34-40` keeps asserting correctly and becomes the runtime
confirmation); the nine Renovate-owned apt pins, including
`OPENJDK_17_JDK_HEADLESS_VERSION` and its `# renovate:` annotation.

**Risk**: `errorJavaVersion` is declared `@VisibleForTesting internal`, which is
not a supported upstream API — Flutter may rename or relocate it without a
deprecation. It is read reflectively rather than parsed from source text: Kotlin
`internal` compiles to a `public` JVM getter with a `$<module-name>` suffix, so
the compiled constant is reachable without `setAccessible` (verified by compiling
the declaration shape and reflecting on it). The getter is matched by name prefix
so an upstream module rename does not break it.

**How a rename surfaces.** The reflective lookup throws, listing the members it
did find. That fails the `updateAndroidVersions` task, which fails
`update-android-version`, which turns the **whole workflow run red** — confirmed
against four historical runs where that job failed and the run still reported
`OVERALL=failure` (`27658604759`, `27587077891`, `27517986487`, `27387574884`).
The job has no `continue-on-error`, and the workflow runs nightly, so the signal
arrives within a day. The failing job's log is what distinguishes a rename from a
transient container or network failure.

Detection is **loud but non-blocking**, by existing design (PR #483): a producer
that emits no block is a carry-forward, not a halt, so the upgrade PR still opens
with the previous `android.java` value and a body annotation linking the failed
job. That annotation reads *"Android toolchain unchanged this cycle"* whether the
producer skipped or failed, so it is a breadcrumb rather than a diagnosis — the red
run is the detector. This is the correct trade-off here: a Flutter rename can only
occur on a version bump, which is exactly when a human is already reviewing the
upgrade PR, and one stale Java major is not worth forfeiting the Flutter bump for
that cycle.

Residual gap, accepted: if the red run is ignored *and* the PR merged, the image
ships the previous Java major, and `test/android.yml` does not catch it because
the manifest and the image agree on the stale value. Two ways to narrow it were
weighed and declined — see design.md's Observability section.
