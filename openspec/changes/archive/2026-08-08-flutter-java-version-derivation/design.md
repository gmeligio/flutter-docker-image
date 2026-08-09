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

The blocker on fixing this was cost: carrying one more value to the build is a
five-file edit. That cost is real but it is a separate concern with its own user
impact, and it is now the change `manifest-build-arg-wiring`. This design assumes
nothing about it: `android_java_version` is passed the way build arguments are
passed at the time of implementation. Full findings in
`../loud-deb-pin-resolution/research.md` (F6, F6b, F7, F10).

## Goals / Non-Goals

**Goals:**

- `android.java.version` becomes a real declaration derived from upstream Flutter,
  on Flutter's cadence rather than the maintainer's.
- The two hand-typed Java strings in `android.Dockerfile` disappear; both follow
  the manifest.
- Per-ARG Docker layer-cache granularity is preserved exactly as today.

**Non-Goals:**

- Reducing the cost of adding a manifest field. Split out as
  `manifest-build-arg-wiring`; this change does not depend on it.

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

### D2 — Read the constant reflectively from the loaded plugin, not by text-parsing

`errorJavaVersion` is declared `@VisibleForTesting internal val` on `object
DependencyVersionChecker`. Kotlin's `internal` is a *module*-scoped compiler
concept, not a JVM one: it compiles to a **`public final`** JVM getter with a
`$<module-name>` mangling suffix. So the value is reachable by ordinary
reflection — no `setAccessible`, therefore no JPMS `--add-opens` and no
illegal-access warnings.

Verified empirically in this session by compiling the exact declaration shape
(`object` + `internal val` of type `org.gradle.api.JavaVersion`) with
`-module-name gradle` and reflecting on it:

```
mangled getters present: [getErrorJavaVersion$gradle, getWarnJavaVersion$gradle]
flutterMinJavaMajor() = 17
```

The class is on the task's own classpath. `flutter create`'s
`settings.gradle.kts` does
`includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`, so the plugin is
a **composite included build** compiled from source at the pinned tag — which is
also why the mangling suffix is `gradle` (the included build's project name) and
why the lookup must match by prefix rather than hardcode it.

```kotlin
val cls = Class.forName("com.flutter.gradle.DependencyVersionChecker")
val instance = cls.getField("INSTANCE").get(null)          // Kotlin object singleton
val getter = cls.methods.firstOrNull {
    it.parameterCount == 0 &&
        JavaVersion::class.java == it.returnType &&          // see below: not optional
        (it.name == "getErrorJavaVersion" || it.name.startsWith("getErrorJavaVersion$"))
} ?: error(
    "Could not find errorJavaVersion getter on DependencyVersionChecker. " +
        "Available: " + cls.methods.map { it.name }.sorted()
)
val javaMajor = (getter.invoke(instance) as JavaVersion).majorVersion.toInt()
```

**The return-type filter is load-bearing, not defensive.** The property is
`@VisibleForTesting`, and Kotlin emits a second method to carry that annotation:
`getErrorJavaVersion$gradle$annotations` — zero-arg, sharing the name prefix,
`static`, returning `void`. `Class.methods` order is unspecified by the JVM, so a
name-only match can select the annotation holder instead of the getter; it
returns `null`, and the cast then fails with `null cannot be cast to non-null
type org.gradle.api.JavaVersion`. This is not hypothetical — it is exactly how
the first implementation failed on the `test-gradle` leg, having passed a local
harness whose mimicked declaration omitted `@VisibleForTesting` and so generated
no holder. Confirmed by `javap` on the real declaration shape:

```
public final org.gradle.api.JavaVersion getErrorJavaVersion$gradle();
public static void getErrorJavaVersion$gradle$annotations();
```

`.majorVersion` is the correct accessor, not `toString()`: the two diverge for
Java 8 (`toString()` → `"1.8"`, `majorVersion` → `"8"`). Verified.

This belongs in `updateAndroidVersions.gradle.kts`, not a separate workflow step.
That task already derives the other four Android values (`platforms`, `gradle`,
`buildTools`, `ndk`) from the live Gradle model, and already reflects over the
AGP extension via `findByType` with a dual-DSL fallback. Java was the only
Android value derived out-of-band by a shell script; this makes it consistent
with its four siblings and deletes a whole workflow step rather than rewriting
one.

Rejected text-parsing
`$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt`:
it reads the *source text* of a file that happens to be on disk, so it breaks on
a file move, a reformat, or a change from `JavaVersion.VERSION_17` to any other
literal form — none of which change the actual value. Reflection reads the
*compiled value the plugin will really enforce*.

Failure mode stays loud, and is more diagnostic than a grep miss. An upstream
rename throws with the available member list — verified by compiling a renamed
variant:

```
IllegalStateException: Could not find errorJavaVersion getter on
DependencyVersionChecker. Available: [equals, getClass,
getMinimumJavaVersion$gradle, hashCode, ...]
```

A thrown exception fails the task, which fails the producer, which per the
existing carry-forward requirement leaves the base-branch `android` block
untouched. No stale value can slip through.

**Trade-off accepted:** reflection over an `internal` member is not a supported
upstream API, and Flutter may rename or relocate it without notice. That is true
of the text-parse too — this change swaps one unsupported read for a
strictly more robust one, and both fail loudly at exactly the moment a human is
reviewing a Flutter upgrade PR. The alternative that avoids upstream coupling
entirely is hand-declaring the value in `config/version.json` and relying on D5's
floor assertion, which reintroduces the maintainer-in-the-loop cost this change
exists to remove.

### D3 — The wiring refactor is a separate change

An earlier draft of this design bundled a rewrite of
`script/setEnvironmentVariables.js`, deriving each ARG name mechanically from its
JSON path. That is split out as `manifest-build-arg-wiring`, for two reasons.

The mechanical rule does not exist. Checked against the names actually in use,
`android.cmake.version` → `cmake_version` drops a segment,
`windows.vsBuildTools.cmakeProject.version` → `vs_cmake_version` abbreviates two,
and `android.ndk.version` → `android_ndk_version` retains the trailing `version`
that a drop-the-suffix rule removes. Any single rule contradicts at least half the
set. Getting that wrong inside this change would have broken every build argument
while nominally shipping a Java fix.

And the two concerns are independent. This change needs `android_java_version` to
reach the Linux build; it does not care whether that costs one table row or four
inline `--build-arg` lines. Keeping them separate means the Java derivation can be
reviewed, landed and reverted on its own.

What this change therefore does: declare `ARG android_java_version` in
`android.Dockerfile`, export `ANDROID_JAVA_VERSION` from
`script/setEnvironmentVariables.js`, and add one `--build-arg` line to each of the
four blocks — the same five edits this repository charges for any manifest field.
It pays that cost rather than pretending it away, which is precisely the argument
for `manifest-build-arg-wiring` existing; if that change lands first, the five
become one table row.

Layer-cache granularity is unaffected: one more scalar build-arg is one more
distinct BuildKit input, exactly like the six today. Two blocks
(`build.yml:156-157`, `release.yml:112-113`) are shared between the android and
web targets, and their comment already records that the android args "are inert
for the web target (its stage declares none of them)". `android_java_version`
joins on those terms — an `UnusedBuildArgs` warning on the web leg, identical in
kind to the six existing ones. Pre-existing condition, not introduced here.

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
config via `docker inspect` and present at runtime).

The `moby/moby#29110` TODOs at `:136-138` ask for something else: deriving
`JAVA_HOME` at build time from `dirname $(dirname $(readlink -f $(which javac)))`,
i.e. capturing shell command *output* into `ENV`. moby#29110 still blocks that and
this change does not unblock it. What changes is that the question stops mattering
— the value arrives as a build argument from a manifest that is itself derived, so
there is nothing left to discover at runtime. The TODOs are therefore **obsoleted
by a different route, not resolved**, and they are replaced by a one-line note
saying so rather than silently deleted. Deleting them outright would read as a
claim that runtime discovery now works.

`ARG android_java_version` must move **above** the `ENV` block (it currently sits
at `:176`, after it).

Division of ownership: the manifest owns the **major** (17), Renovate owns the
**patch** (`17.0.20+8-1~deb12u1`). A major bump remains a deliberate human change —
it is an ARG *rename* plus a suite change, not a value bump — but CI now fails
loudly on divergence instead of shipping silently.

### D5 — Floor assertion in the Gradle task

`check(JavaVersion.current().majorVersion.toInt() >= javaMajor)` in
`updateAndroidVersions.gradle.kts`, where `javaMajor` is the value D2 just
derived. Circular as a *derivation*, but valid as an *assertion*.

**It is narrower than it looks, and worth being precise about.** Both invocation
sites — `update-version.yml:286-290` and `build.yml:494-498` — run the task inside
`ghcr.io/<owner>/flutter-android:<version>`, an image whose JDK this change makes
derive from the very field being asserted. So in steady state the check compares a
value against itself and can never fire. What it actually guards is the **lag
window on a floor bump**: the container is the *previously published* image, so on
the cycle where Flutter raises `errorJavaVersion` from N to N+1, the task derives
N+1 while running on a JDK N container and fails immediately, naming the required
minimum. Without it, that cycle instead fails deeper inside Flutter's own
`checkJavaVersion` with a less direct message, or — if nothing in the task happens
to invoke that path — writes a manifest the running toolchain cannot satisfy.

That is one cycle per floor bump, which is rare. The assertion is cheap and the
failure it converts is confusing, so it earns its place; it is not a general
guard on the installed JDK.

Because D2 puts the derivation in this same task, the assertion compares against
the derived value rather than a restated literal — so there is no second `17` to
drift.

## Automated Test Strategy

No new test infrastructure. The change is covered by three gates that already run:

1. **`test/android.yml:34-40`** — asserts the built image's `java -version` major
   equals `android.java.version`. Generated from the manifest via
   `config/android.cue:33` and `script/update_test.sh:16`, both of which already
   read `android.java.version`. This is the critical path: it is what turns a
   wrong `JAVA_HOME` or a wrong package name red, and it needs no edit.
2. **`cue vet config/schema.cue -d '#Version'`** — `android.java` is already
   `#PlatformVersion` (an int) at `config/schema.cue:46`; a non-integer derivation
   fails the producer before it emits.
3. **`git diff --exit-code`** after `script/update_test.sh` (`build.yml:412-414`)
   — catches a manifest change not reflected in the regenerated test.

Beyond those, the only check this change adds is that `android_java_version`
actually reaches the build: the Linux build's `--build-arg` set goes from the
current six (run `31194164846` shows the present form) to seven, with the six
existing names and values untouched. If `manifest-build-arg-wiring` has landed
first, its own byte-identical baseline check covers the six; this change is then
purely the seventh. Either ordering, the assertion is the same — six unchanged,
one added.

The floor assertion (D5) is self-testing: it runs on every
`update-android-version` and `test-gradle` invocation.

## Observability

**Failure paths, all loud:**

| Failure | Surfaces as |
|---|---|
| Upstream renames/removes `errorJavaVersion` | Reflection lookup throws with the available member list → Gradle task fails → producer fails → base block carried forward |
| Derived value is not a positive integer | `cue vet` non-zero in the producer's own validation step |
| Dockerfile ships a JDK major ≠ manifest | `test/android.yml` "Java is pinned" turns the PR check red |
| `android_java_version` not passed to the build | Empty `ARG` → `apt-get install openjdk--jdk-headless=…` fails at the consuming `RUN` |
| Flutter raises its floor above the JDK in the *previously published* image the task runs inside | `check(...)` fails the Gradle task, naming the minimum (D5 — the lag-window case, not a general JDK guard) |

**Cannot fail silently.** The one previously-silent path — a hand-typed
`JAVA_HOME` disagreeing with the installed JDK — is closed by D4, since both now
derive from one value.

**What a maintainer actually sees when Flutter renames the constant.** Three
signals, in descending reliability:

1. **The workflow run goes red.** `update-android-version` has no
   `continue-on-error`, and a failed producer fails the run even though
   `compose-and-open-pr` continues under `!cancelled()`. Verified against four
   historical runs where exactly this happened — `27658604759`, `27587077891`,
   `27517986487`, `27387574884`, all `OVERALL=failure`. The workflow runs nightly
   (`cron: '0 0 * * MON-FRI'`), so the signal arrives within a day.
2. **The job log names the cause.** The `error(...)` prints the sorted member
   list, which is what separates "Flutter renamed the constant" from a transient
   container-pull or network failure. Without opening the log the two are
   indistinguishable.
3. **The PR body annotates the empty block** (`update-version.yml:428-431`),
   linking the failed job. Weak on its own: the wording is *"Android toolchain
   unchanged this cycle"* whether the producer skipped or failed. Treat it as a
   breadcrumb, not a diagnosis.

**Non-blocking, deliberately.** PR #483 made the three platform updaters
structurally symmetric, explicitly removing the old asymmetry where "Windows-job
failure was soft […]; Android-job failure was hard (PR blocked)." A producer that
emits no block is a carry-forward, not a halt — so the upgrade PR still opens with
the previous `android.java`. That is the right trade-off here: a rename can only
land on a Flutter version bump, which is exactly when a human is reviewing the
upgrade PR, and one stale Java major does not justify forfeiting the Flutter bump.
No change to that model is proposed; a reflection failure is just another
empty-block cycle.

**Residual gap, accepted.** If the red run is ignored *and* the PR merged, the
image ships the previous Java major. `test/android.yml`'s "Java is pinned"
assertion does **not** catch this — manifest and image would agree on the stale
value. The red run is the only guard on that path.

Two ways to narrow it were considered and both declined, for different reasons:

- **Fail `compose-and-open-pr` when the block is empty *and* a producer failed.**
  This would close the gap outright, but it re-splits the three platform updaters
  that PR #483 deliberately made symmetric — Android failure would block the PR
  again while Windows failure did not. Reintroducing that asymmetry to guard one
  rare field is the wrong trade.
- **Word the PR annotation differently for failure vs. skip.** Cheaper, and it
  addresses the "breadcrumb, not a diagnosis" complaint directly: the reader would
  see *"Android toolchain producer failed"* rather than *"unchanged this cycle."*
  Declined here only because it changes shared workflow text on behalf of all
  three producers, which is a separate concern from Java derivation and should be
  proposed as one. Worth doing.

**Logging**: the Gradle task should print the derived constant and the resolved
getter name (`Derived Java major from errorJavaVersion (getErrorJavaVersion$gradle): 17`)
so a job log shows the value, its provenance, *and* the mangled name it matched —
the last being the detail that makes a future upstream rename diagnosable at a
glance.

## Risks / Trade-offs

**[Reflection targets an `internal`, unsupported member]** → Accepted, with eyes
open. `internal` signals "not upstream API", and Flutter can rename or relocate
`errorJavaVersion` without a deprecation. Mitigated three ways: the prefix match
plus return-type filter tolerates a module rename (the most likely churn, since
the suffix is the included build's project name) while still distinguishing the
getter from its `@VisibleForTesting` annotation holder; the lookup throws with the available member list,
so the fix is obvious from the log; and the pinned tag means it cannot break
spontaneously — only when the Flutter version bumps, which is exactly when a human
is reviewing the upgrade PR. The rejected text-parse carried the same coupling
with a worse failure signal.

**[Kotlin name mangling changes shape]** → The `$<module>` suffix convention is
long-stable and the prefix match covers both mangled and unmangled forms. If
Kotlin ever changed it, the lookup throws rather than silently returning a wrong
value.

**[The ARG name outlives the major it carries]** → `android_java_version` becomes
`21` when Flutter's floor moves, while the patch pin is still named
`OPENJDK_17_JDK_HEADLESS_VERSION` with a `suite=bookworm depName=openjdk-17-…`
annotation. Renovate keeps tracking openjdk **17** patches while the image installs
**21**, so the pin goes stale under a name that looks current. Nothing catches it:
`test/android.yml` asserts the major, not the patch. A major bump is therefore a
deliberate multi-line edit — rename the ARG, update the annotation — and this is
recorded as a follow-up issue rather than solved here, because solving it means
deriving the ARG name too, which breaks Renovate's regex-adjacency requirement.

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

1. **D1/D2/D5 — add** the derivation to `updateAndroidVersions.gradle.kts`
   alongside the other four Android values, plus the floor assertion, **leaving
   the old `script/java_version.sh` step in place**. Both write
   `android.java.version` on the same run, so agreement shows up as an empty diff
   and disagreement as a visible one. That empty diff *is* the validation, and it
   is a stronger check with the old path still present than without. D5 lands here
   because it consumes D2's derived value in the same task.
2. **Delete the old path** — `script/java_version.sh` and the workflow step that
   ran it — once step 1 has confirmed agreement.
3. **D4** (Dockerfile follows) — the first step that can change the built image.
   `test/android.yml` gates it.

Rollback: each step is a separate commit; step 3 is the only one that touches the
published image, and reverting it restores the hand-typed strings.

`manifest-build-arg-wiring` is not in this sequence and does not gate it (D3).

## Open Questions

None. Both questions this change raised are answered below.

## Resolved

**Does the Windows image need a Java major? No.** Grepping `windows.Dockerfile`
and `.github/workflows/windows-image.yml` for `java`/`jdk` returns nothing — the
Windows leg installs no JDK, so there is no second hand-typed major to unify. The
ADDED requirement *"The image's JDK major follows the manifest"* names
`android.Dockerfile` explicitly for that reason, rather than binding both
Dockerfiles. If the Windows image ever grows a JDK it should read the same
manifest field.


**Should `readme.md` publish the Java version? No.** The README never mentions
Java — grepping `readme.md` and `docs/*.mjs` returns nothing — so there is no
published value to keep in step, and adding one would create a fourth place the
Java major has to agree. The manifest and the image are the two that matter, and
`test/android.yml` already binds them.

This matters beyond the README, because the main spec's requirement *"Android
producer derives the installed Java major version"* currently states its
experience context as *"the CI engineer reading the README's Java version"*
(`openspec/specs/flutter-version-update/spec.md:192`) — a reader who does not
exist. The delta replaces that context rather than inheriting it, so archiving
this change also corrects a spec that described a README section never written.
