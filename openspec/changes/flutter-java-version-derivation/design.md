## Context

`config/version.json` is the repository's single version manifest. Sixteen values
reach the Docker build through it; nine Debian apt pins reach the build separately
via Renovate-annotated `ARG` literals in `android.Dockerfile`. That split is
deliberate and stays (Renovate's regex manager needs the value adjacent to its
annotation).

Java sits in neither lane properly. `android.java.version` is written by
`update-version.yml:296-303`, which runs `script/java_version.sh` inside the
*previously published* container. The value therefore describes the last build and
cannot affect the next one. What actually determines the shipped JDK is two
hand-typed strings — `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`
(`android.Dockerfile:140`) and the `openjdk-17-jdk-headless` package name (`:164`)
— neither of which any check covers.

The blocker on fixing this was cost: `script/setEnvironmentVariables.js` hand-lists
ten `core.exportVariable` calls and the build-args block is copy-pasted four times,
so carrying one more value is a five-file edit. Full findings in
`../loud-deb-pin-resolution/research.md` (F6, F6b, F7, F10).

## Goals / Non-Goals

**Goals:**

- `android.java.version` becomes a real declaration derived from upstream Flutter,
  on Flutter's cadence rather than the maintainer's.
- The two hand-typed Java strings in `android.Dockerfile` disappear; both follow
  the manifest.
- Adding any future manifest field costs one edit, not five.
- Per-ARG Docker layer-cache granularity is preserved exactly as today.

**Non-Goals:**

- Migrating to Java 21. Decided against (research F6); Flutter scaffolds 17 and
  publishes no recommended version above the floor.
- Renovate `mode: full` / PR #531 (Track A) — independent, does not gate this.
- Moving the nine apt pins into `version.json` — rejected in research F10.
- Deleting the nine dead scripts, the `cmdlineTools` mirror, or the dead `30.0.3`
  job-env lines. Real, recorded, separate.

## Decisions

### D1 — Derive Java from `errorJavaVersion`, not `sourceCompatibility`

Flutter defines **no recommended or maximum Java version**. Verified at commit
`3594a632`: `gradle_utils.dart` carries `maxKnownAndSupportedGradleVersion` (:85),
`maxKnownAndSupportedKgpVersion` (:91) and `maxKnownAndSupportedAgpVersion` (:98)
but no Java equivalent. Only a floor exists — `gradle_utils.dart:72-73` and
`DependencyVersionChecker.kt:99,101`, all four `17`, with no warn band.

Rejected `compileOptions.sourceCompatibility` despite it reading `17` today: it is
a *bytecode target*, not a JDK requirement (JDK 21 emits 17 bytecode via
`--release`), and it lives in the generated app's `build.gradle.kts`, which
Flutter's inline TODOs invite users to edit. Right answer today, wrong reason.

Rejected `JavaVersion.current()` as fully circular — it reports the JDK the
Dockerfile already installed.

Following the floor means the value moves when *Flutter* moves it, one release
after the `warn` bump telegraphs the change
(`DependencyVersionChecker.kt:87-91`). Tracking anything else puts the maintainer
back in the loop, which is the cost this change exists to remove.

### D2 — Text-parse the pinned checkout, not an API call

`errorJavaVersion` is `internal` + `@VisibleForTesting`, and
`checkDependencyVersions()` returns `Unit`. The only externally observable output
is the boolean `usesUnsupportedDependencyVersions` extra property, which reports
*that* something is out of range, never *what is required*. There is no API to
call.

So `update-android-version` greps the constant out of
`$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt`
— already on disk in the container, at the exact pinned tag. This matches the
upstream-parsing pattern the same workflow already runs for the Windows vsman
(`update-version.yml:171-172`).

Failure mode is loud by construction: an upstream file move or constant rename
yields an empty match, which fails the step, which fails the producer, which per
the existing carry-forward requirement leaves the base-branch `android` block
untouched. No stale value can slip through.

### D3 — Mechanical ARG-name derivation, single emission point

`setEnvironmentVariables.js` walks the manifest and derives each ARG name from its
JSON path (`android.ndk.version` → `android_ndk_version`), emitting the entire
build-args block as one `BUILD_ARGS` value. The four call sites become
`build-args: ${{ env.BUILD_ARGS }}`.

**Layer caching is the constraint that shapes this.** The tempting simplification
— pass the manifest as one JSON build-arg, or `COPY config/version.json` into the
build — would make any version change invalidate every layer below. Builds run
15–25 minutes and lean on registry buildcache (`build.yml:151-152`), so a fastlane
bump must not rebuild the Flutter clone. Emitting N newline-separated
`name=value` pairs keeps BuildKit seeing N distinct build-args exactly as today.
Only *authoring* is centralized; the wire format is unchanged.

The manifest has nested shapes that do not map to a scalar (`android.platforms` is
an array joined with spaces; `windows.vsBuildTools.*` nests two deep). Derivation
handles the flat `{version: X}` and `{build: X}` leaf shapes mechanically and
keeps an explicit table for the handful that need transformation — smaller than
today's ten hand-listed exports, and the exceptions are visible rather than
implied.

### D4 — Dockerfile follows the derived value

```dockerfile
ARG android_java_version

ENV ANDROID_HOME="$SDK_ROOT/android-sdk" \
    JAVA_HOME="/usr/lib/jvm/java-${android_java_version}-openjdk-amd64"

# renovate: suite=bookworm depName=openjdk-17-jdk-headless
ARG OPENJDK_17_JDK_HEADLESS_VERSION="17.0.20+8-1~deb12u1"

RUN apt-get install -y --no-install-recommends \
    "openjdk-${android_java_version}-jdk-headless=$OPENJDK_17_JDK_HEADLESS_VERSION" \
```

ARG→ENV interpolation within a stage was **verified empirically** in this session
(`RUNTIME_ENV=[/usr/lib/jvm/java-17-openjdk-amd64]`, confirmed baked into the image
config via `docker inspect` and present at runtime). The `moby/moby#29110` TODOs at
`:136-138` concern a different limitation — capturing shell command *output* in
`ENV` — which remains unsupported; those TODOs are resolved by this change only in
the sense that the value now arrives from CI rather than needing runtime discovery.

`ARG android_java_version` must move **above** the `ENV` block (it currently sits
at `:176`, after it).

Division of ownership: the manifest owns the **major** (17), Renovate owns the
**patch** (`17.0.20+8-1~deb12u1`). A major bump remains a deliberate human change —
it is an ARG *rename* plus a suite change, not a value bump — but CI now fails
loudly on divergence instead of shipping silently.

### D5 — Floor assertion in the Gradle task

`check(JavaVersion.current() >= JavaVersion.VERSION_17)` in
`updateAndroidVersions.gradle.kts`. Circular as a *derivation*, but valid as an
*assertion*: it fails the build if the installed JDK drops below what Flutter
enforces. One line, catches the failure mode that actually matters.

## Automated Test Strategy

No new test infrastructure. The change is covered by three gates that already run:

1. **`test/android.yml:34-40`** — asserts the built image's `java -version` major
   equals `android.java.version`. Generated from the manifest via
   `config/android.cue:33` and `script/update_test.sh:16`, both of which already
   read `android.java.version`. This is the critical path: it is what turns a
   wrong `JAVA_HOME` or a wrong package name red, and it needs no edit.
2. **`cue vet config/schema.cue -d '#Version'`** — `android.java` is already
   `#PlatformVersion` (an int) at `config/schema.cue:47`; a non-integer derivation
   fails the producer before it emits.
3. **`git diff --exit-code`** after `script/update_test.sh` (`build.yml:412-414`)
   — catches a manifest change not reflected in the regenerated test.

For D3, the meaningful check is that the emitted `BUILD_ARGS` produces the same
`--build-arg` set as today. Verify by comparing the `docker buildx build` command
line in a CI run against the current baseline (run `31194164846` shows the
present form) — same six args, same values, before adding the seventh.

The floor assertion (D5) is self-testing: it runs on every
`update-android-version` and `test-gradle` invocation.

## Observability

**Failure paths, all loud:**

| Failure | Surfaces as |
|---|---|
| Upstream moves/renames `errorJavaVersion` | Empty grep match → step fails → producer fails → base block carried forward |
| Derived value is not a positive integer | `cue vet` non-zero in the producer's own validation step |
| Dockerfile ships a JDK major ≠ manifest | `test/android.yml` "Java is pinned" turns the PR check red |
| `BUILD_ARGS` omits a value | Empty `ARG` → build fails at the consuming `RUN` |
| Installed JDK below Flutter's floor | `check(...)` fails the Gradle task |

**Cannot fail silently.** The one previously-silent path — a hand-typed
`JAVA_HOME` disagreeing with the installed JDK — is closed by D4, since both now
derive from one value.

**Logging**: the derivation step should echo the parsed constant
(`Derived Java major from errorJavaVersion: 17`) so a job log shows the value and
its provenance, matching the existing `echo "Derived Java major: $java_major"` it
replaces.

## Risks / Trade-offs

**[Upstream file move breaks the grep]** → Fails loudly (empty match → failed
step), never silently stale. The pinned tag means it cannot break spontaneously —
only when the Flutter version bumps, which is exactly when a human is reviewing the
upgrade PR.

**[`BUILD_ARGS` becomes an opaque blob in workflow YAML]** → The four call sites no
longer show which args are passed. Mitigated by the job log printing the resolved
value, and by the manifest itself being the readable list. Net legibility improves:
one authoritative list replaces four copies that could disagree.

**[Derivation logic must handle nested manifest shapes]** → D3 keeps an explicit
table for the non-scalar cases rather than over-generalizing. Risk is bounded: the
manifest has 16 values and changes rarely.

**[Renovate's regex must still match the openjdk ARG]** → The `# renovate:`
annotation and `ARG OPENJDK_17_JDK_HEADLESS_VERSION="…"` line are untouched by D4;
only the `RUN` line that *consumes* them changes. `renovate.json`'s `matchStrings`
targets the ARG declaration, not the usage.

**[Ordering: `ARG` must precede the `ENV` that interpolates it]** → Mechanical, but
easy to get wrong silently — an ARG declared after the ENV yields an empty
interpolation and a `JAVA_HOME` of `/usr/lib/jvm/java--openjdk-amd64`. The
`test/android.yml` Java assertion catches it.

## Migration Plan

Sequenced so each step is independently revertable:

1. **D3 first** (self-wiring build-args), verifying the emitted `--build-arg` set
   is byte-identical to today's. No behaviour change — pure refactor, easy to
   confirm and revert.
2. **D1/D2** (derive Java) — swap the derivation source; `version.json` should
   still read `17`, so the diff on the manifest is empty. That empty diff *is* the
   validation.
3. **D4** (Dockerfile follows) — the first step that can change the built image.
   `test/android.yml` gates it.
4. **D5** (floor assertion) — additive.

Rollback: each step is a separate commit; step 3 is the only one that touches the
published image, and reverting it restores the hand-typed strings.

## Open Questions

1. **Should `readme.md` publish the Java version?** It currently never mentions
   Java (grepped). Once `version.json` is a real declaration, `docs/build.mjs`
   could surface it nearly free. Maintainer call, not blocking.
2. **Does `windows.Dockerfile` adopt D3's `BUILD_ARGS`?** The Windows leg builds
   without buildx (`windows-image.yml:130-149` hand-assembles a PowerShell array),
   so it needs a different shape. Out of scope here; the Linux legs are the four
   duplicated blocks this change targets.
