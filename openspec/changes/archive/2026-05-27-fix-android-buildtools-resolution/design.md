## Context

`update_version.yml` produces the monthly Flutter upgrade PR. The `update_android_version` job's job is to resolve every Android tooling version that downstream image builds will need, so that `android.Dockerfile` can pre-install them and the smoke test in `test/android.yml` can assert "nothing was downloaded at container runtime."

Today the job uses two sources of truth, asymmetrically:

```
SOURCE A — packages.txt (web fetch)        SOURCE B — flutter create + Gradle
─────────────────────────────────          ───────────────────────────────────
build-tools  ← awk first entry             compileSdk   ← flutter.compileSdkVersion
                                           targetSdk    ← flutter.targetSdkVersion
                                           ndk          ← flutter.ndkVersion
                                           gradle       ← gradle.gradleVersion
```

Source A was added in 2024 when AGP's build-tools selection was loosely correlated with the highest version listed for the Flutter tag. Since AGP 9.0, the bundled `buildToolsVersion` constant the plugin enforces no longer tracks "newest available" — it tracks "what AGP was tested against." Concretely:

- `flutter@3.44.0:engine/src/flutter/tools/android_sdk/packages.txt:3` lists `build-tools;36.1.0,build-tools;35.0.0,...` — the workflow extracts `36.1.0`.
- `flutter@3.44.0:packages/flutter_tools/lib/src/android/gradle_utils.dart:43` pins AGP templates to `9.0.1`.
- AGP 9.0.1 defaults `buildToolsVersion` to `36.0.0`. Flutter does not override this anywhere (verified by grep of `packages/flutter_tools/gradle/` and `packages/flutter_tools/templates/` at tag 3.44.0; zero matches for `buildToolsVersion`).
- Result on PR #470 / #471: image installs `36.1.0`; `flutter create test_app && ./gradlew bundleRelease` asks sdkmanager for `build-tools;36.0.0`; sdkmanager installs it at container runtime; `test/android.yml`'s `excludedOutput: [Checking, Installing, Downloading]` trips.

The CI engineer reviewing the PR sees a red required check on the smoke test with no clear pointer back to the resolution mismatch — the failing assertion's error message says "Excluded string 'Checking' found in output", not "the image was built against the wrong build-tools version."

## Goals / Non-Goals

**Goals:**

- Make the image's pre-installed `build-tools/X.Y.Z` always equal the version AGP requests at build time for a freshly-created Flutter project at the target Flutter tag.
- Collapse the two sources of truth into one: the Gradle script `updateAndroidVersions.gradle.kts` already reads four out of five Android values from AGP; it should read the fifth too.
- Remove the now-unjustifiable workflow step that fetches `packages.txt` over HTTP just for one field.
- Keep the existing schema validation (`cue vet`) and the per-producer validation gate from `Requirement: Producer jobs validate their own version.json before upload` unchanged.

**Non-Goals:**

- Reworking the `compose_version_manifest` flow that `p12-symmetric-platform-updates` introduces. This change is orthogonal: it modifies what value Android's job writes for `buildTools.version`, not how Android's fragment composes with Windows's. The two changes can land in either order.
- Detecting other AGP-vs-image drift surfaces (NDK, cmake, platforms). The existing `flutter create`-driven path already reads those from AGP; only build-tools is affected.
- Adding logic to handle AGP versions that *do* override `buildToolsVersion` in the template — Flutter has never done this; if a future Flutter tag introduces it, the same Gradle-extension read will pick it up automatically (that's the point).

## Decisions

### Decision 1: Read `buildToolsVersion` from the AGP extension inside the Gradle task

Inside `updateAndroidVersions.gradle.kts`, after `flutter create test_app` has produced an Android Gradle project with AGP applied, read the resolved build-tools version from AGP's DSL extension on the **project** (not the surrounding Task — `extensions` inside a `doLast { }` lambda resolves to the Task's extension container, which doesn't carry the `android { }` registration).

AGP exposes two DSL surfaces depending on the `android.newDsl` Gradle property:

- `android.newDsl=true` (AGP 9.0 default for new projects, AGP 10.x universal): the registered extension is `com.android.build.api.dsl.ApplicationExtension`.
- `android.newDsl=false` (still used by Flutter 3.44.0's generated `gradle.properties` to keep the legacy DSL active during AGP 9 transition): the registered extension is `com.android.build.gradle.AppExtension` (legacy DSL).

The script tries the new DSL first, falls back to the legacy one, and errors loudly if neither is present:

```kotlin
val buildToolsVersion: String = project.extensions
    .findByType(com.android.build.api.dsl.ApplicationExtension::class.java)
    ?.buildToolsVersion
    ?: project.extensions
        .findByType(com.android.build.gradle.AppExtension::class.java)
        ?.buildToolsVersion
    ?: error("Could not resolve buildToolsVersion from the AGP extension on project ${project.path}")
```

The dual-surface read future-proofs against Flutter dropping `android.newDsl=false` from its generated `gradle.properties` (which AGP deprecation warnings during the test run flag as imminent).

**Rationale**: AGP is the system that *acts on* this value at runtime. Asking AGP what it will request is the only source of truth that cannot drift from what AGP actually requests. Every other heuristic is, by construction, an approximation.

**Alternatives considered:**

- **Pin to AGP's hardcoded default by parsing AGP's source.** Fragile; requires tracking AGP releases. Rejected.
- **Install every build-tools version `packages.txt` lists.** Doubles image weight; doesn't solve the resolution problem if AGP ever picks something not in `packages.txt`. Rejected.
- **Pick the *last* entry of `packages.txt`** (which happens to be the AGP default today). Coincidentally correct for 3.44.0; semantically wrong — `packages.txt` ordering is "preferred first," not "AGP-default last." Will silently break. Rejected.

### Decision 2: Delete the `BUILD_TOOLS_VERSION` env var plumbing

Today `updateAndroidVersions.gradle.kts:16-17` errors out if the env var is missing. After Decision 1, the env var is dead. Remove both:

- The env-var read in `updateAndroidVersions.gradle.kts`.
- The "Update Android SDK build tools version" step in `update_version.yml` (lines 291-296) that computes it via `curl … | awk …`.
- The `BUILD_TOOLS_VERSION:` env mapping in the next step (line 313).

**Rationale**: Decision 1 makes the env var redundant. Removing it eliminates one source of drift (no chance of "env var said X, Gradle wrote Y") and one network dependency (the workflow no longer needs to reach `raw.githubusercontent.com` for `packages.txt` just for this).

### Decision 3: Delete `script/latest_android_sdk_build_tools.sh`

The file is a two-line scratchpad referencing Flutter `3.35.1`. Repo grep (`rg latest_android_sdk_build_tools`) confirms no workflow or script invokes it. Delete to avoid leaving behind a misleading "this is how we resolve build-tools" hint.

**Alternative**: leave it as a comment in `update_version.yml`. Rejected — comments rot; the spec is the durable record.

### Decision 4: Spec delta uses MODIFIED on `flutter-version-update`'s existing requirement, not a new requirement

The existing `Requirement: Upgrade PR contains a coherent, validated version.json` (`openspec/specs/flutter-version-update/spec.md:28-77`) pins the *resolution rule* for `buildTools.version` in its prose and in two scenarios (lines 36-48). Both must change. The Windows / VS BuildTools / cue-vet portions of the same requirement are unchanged.

Use a single MODIFIED block that restates the full requirement (prose + all scenarios) with the build-tools resolution rule swapped. The Windows-skip and schema-valid scenarios are copied verbatim. The two build-tools scenarios are replaced with one new scenario tied to the AGP-resolved value.

**Rationale**: This is the openspec convention for MODIFIED — "MUST include full updated content." Partial-content MODIFIED loses detail at archive time.

## Risks / Trade-offs

- **[AGP API shape varies across AGP majors]** → The Gradle task lives inside the app module of `flutter create`, so the AGP version is dictated by the target Flutter tag. End-to-end verification during apply revealed two API-shape facts that the implementation handles explicitly: (1) `extensions` inside `doLast { }` is the Task's extension container, not the Project's — must qualify as `project.extensions`; (2) AGP exposes either `ApplicationExtension` (newDsl=true) or `AppExtension` (newDsl=false), and Flutter 3.44.0 still pins the latter. Mitigation: try the new DSL first, fall back to the legacy DSL, error loudly if neither resolves (see Decision 1 for the snippet). Validated at apply time inside `docker.io/gmeligio/flutter-android:3.41.9` (emits `35.0.0`, matches committed value) and `ghcr.io/gmeligio/flutter-android:pr-471` for Flutter 3.44.0 (emits `36.0.0`, matches AGP-default).
- **[`updateAndroidVersions` task runs before `bundleRelease`, so the value AGP reports is the *configured* value, not the *requested* value]** → For AGP, those are the same: AGP's `buildToolsVersion` extension property holds either the user-set override or AGP's bundled default; AGP uses exactly that string to look up the SDK package. No transformation happens later. Mitigation: the smoke test in `build.yml` is itself the end-to-end validation; the next monthly upgrade PR will surface any divergence as the same red check we're fixing today.
- **[`packages.txt` may still be authoritative for cmake / ndk versions in some Flutter releases]** → Out of scope for this change. The script already reads ndk from `flutter.ndkVersion` and cmake is not currently resolved from `packages.txt` (it is read from upstream `version.json` directly). No change.
- **[The Dockerfile may pin `android_build_tools_version` from `version.json`, and an unrelated workflow could install a different version]** → Grep at apply time confirms `android.Dockerfile` uses `${android_build_tools_version}` consistently and that no other workflow installs build-tools. The Dockerfile reads its value from the same `config/version.json` Decision 1 writes — single source of truth maintained.

## Automated Test Strategy

- **Spec-level scenarios** in `specs/flutter-version-update/spec.md` are the durable assertions; each maps to a CI observation.
- **End-to-end test** is the existing `test/android.yml` smoke test that ships with every image. After this change, an upgrade PR for any Flutter tag whose AGP default differs from `packages.txt`'s first entry will *no longer* trip `excludedOutput: [Checking, Installing, Downloading]`. The smoke test thus doubles as the regression gate — without modifying it, the next monthly upgrade PR is the integration test.
- **Manual verification at apply time**: run the updated `updateAndroidVersions.gradle.kts` locally against `flutter create test_app` at Flutter 3.44.0 and confirm the emitted `config/version.json` contains `android.buildTools.version == "36.0.0"`. Repeat against 3.41.9 (the currently committed Flutter version) and confirm it still emits the version that committed `config/version.json` already pins (`35.0.0`). If 3.41.9 emits something different, that is itself a finding — it would mean today's pinned image has a latent drift.
- **No new unit tests** are warranted. The Gradle task is a five-line read; the production "test" is the spec scenario plus the smoke test.

## Observability

- **Workflow failure surfaces in the Actions tab** as today: a malformed `buildTools.version` written by the Gradle task fails the per-producer `cue vet` step (`Requirement: Producer jobs validate their own version.json before upload`), which fails the `update_android_version` job, which skips the PR. The CI engineer sees the failing job pointing at the producer.
- **Silent failure path eliminated**: the deleted `curl … | awk …` step had a known silent-failure mode (empty pipe → empty `buildTools.version` → schema rejection downstream with a confusing message). Removing the step removes the failure mode.
- **No new log lines required**. The Gradle task already prints the composed JSON via `println(prettyStr)` (`script/updateAndroidVersions.gradle.kts:36`); the AGP-resolved value will appear in that print line and in the uploaded artifact.
- **End-user observability** of the underlying contract ("no runtime SDK downloads") is unchanged: it is the `test/android.yml` smoke test's `excludedOutput` clause, which fails the build.yml image-test job when violated.

## Migration Plan

1. Update `script/updateAndroidVersions.gradle.kts` to read `buildToolsVersion` from the AGP extension.
2. Update `.github/workflows/update_version.yml` to delete the build-tools fetch step and the env-var passthrough.
3. Delete `script/latest_android_sdk_build_tools.sh` after grep confirms zero callers.
4. Update the spec delta in this change (proposal + specs/flutter-version-update/spec.md).
5. On the same branch, hand-edit `config/version.json` to set `android.buildTools.version` to `36.0.0` and `test/android.yml`'s `expectedOutput` to match, so the existing in-flight Flutter 3.44.0 upgrade is unblocked in the same PR. (Alternatively, land this change first, then re-run `update_version.yml` to regenerate the 3.44.0 upgrade PR from scratch — but bundling is faster.)
6. Verify `build.yml` smoke tests pass.

**Rollback**: revert the commit. The workflow returns to the awk-based heuristic. Any in-flight PR whose `config/version.json` was generated under the new rule remains valid (`36.0.0` is a real build-tools version; the only change is which version gets picked).

## Open Questions

(none — all decisions are grounded in either the codebase or Flutter @3.44.0 source.)
