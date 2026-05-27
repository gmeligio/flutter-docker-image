## Why

`update_version.yml` resolves Android `buildTools.version` from the *first* entry of Flutter's upstream `engine/src/flutter/tools/android_sdk/packages.txt`. That file is Google's CIPD mirror manifest — what Google pre-stages on its own CI — not what the Android Gradle Plugin (AGP) actually requests when building a freshly-created Flutter project. For Flutter 3.44.0, `packages.txt` lists `build-tools;36.1.0` first, but the AGP version Flutter 3.44.0 templates pin (9.0.1) defaults to `buildToolsVersion = 36.0.0`. PR #470 (Flutter 3.44.0 upgrade) caught the regression: the smoke test `flutter create test_app && ./gradlew bundleRelease` made Gradle download `build-tools;36.0.0` at container runtime, tripping `test/android.yml`'s `excludedOutput: [Checking, Installing, Downloading]` and red-failing the monthly upgrade PR. Every future AGP bump where the CIPD-preferred version diverges from the AGP-default version will recur. The promise of the image — "no runtime SDK downloads for a vanilla Flutter project" — depends on resolving the same value AGP will ask for, not a sibling-but-different manifest.

## What Changes

- **BREAKING (workflow / spec):** Change the resolution source for `android.buildTools.version` from `engine/src/flutter/tools/android_sdk/packages.txt` (extracted via shell `awk`) to the AGP-resolved `buildToolsVersion` read from the Gradle project AGP creates inside `flutter create test_app`. The script `script/updateAndroidVersions.gradle.kts` (which already reads `compileSdkVersion`, `targetSdkVersion`, `ndkVersion`, and `gradleVersion` from the same project) becomes the single source of truth. Remove the `BUILD_TOOLS_VERSION` env-var coupling; `updateAndroidVersions.gradle.kts` reads `android.buildToolsVersion` from the AGP extension instead of `System.getenv`.
- **MODIFIED (workflow):** Delete the "Update Android SDK build tools version" step (`.github/workflows/update_version.yml:291-296`) that performs the `curl … packages.txt | awk …` extraction and the env-var plumbing on the following Gradle step.
- **MODIFIED (script):** Delete `script/latest_android_sdk_build_tools.sh` (vestigial; was the basis for the awk heuristic and is not invoked by any workflow). Verify by repo-wide grep before removal.
- Add a CUE-level assertion (or shell post-check in the workflow) that the build-tools version pre-installed by `android.Dockerfile` matches `android.buildTools.version` in `config/version.json` — closing the loop so a future drift between "what AGP wants" and "what the image installs" surfaces in CI rather than at customer build time.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `flutter-version-update`: the requirement that the upgrade PR's `version.json` contains the *first* build-tools entry from `packages.txt` is replaced by a requirement that it contains the build-tools version AGP resolves inside a freshly-created Flutter project at the target Flutter tag. The two scenarios that pin the old heuristic (single-entry packages.txt → first entry; multi-entry comma-joined line → highest) are replaced by scenarios that pin the new heuristic (AGP default; explicit `android.buildToolsVersion` in template — if Flutter ever sets one). The "schema validation catches malformed `buildTools.version`" scenario is preserved unchanged.

## Impact

- Affected files: `.github/workflows/update_version.yml` (deletes one step, drops one env var), `script/updateAndroidVersions.gradle.kts` (reads buildToolsVersion from AGP extension instead of env var), `script/latest_android_sdk_build_tools.sh` (deleted). Possibly `config/schema.cue` (no contract change, but the spec-level invariant tightens). No image-build workflow or Dockerfile changes — the image continues to install whatever `config/version.json` specifies; only how that JSON gets produced changes.
- Risk: AGP's API for reading the resolved `buildToolsVersion` from the extension differs between AGP 8 and AGP 9. Mitigation: the Gradle script runs inside `flutter create test_app`, whose AGP version is dictated by the target Flutter tag — so the API surface matches the AGP Flutter pins. The script's existing pattern (`flutter.compileSdkVersion`, `flutter.ndkVersion`) demonstrates the convention.
- Risk: deleting `latest_android_sdk_build_tools.sh` breaks an undiscovered consumer. Mitigation: pre-deletion `rg latest_android_sdk_build_tools` across the repo; the file is documentation-style with a single hard-coded Flutter tag (`3.35.1`), so consumption is unlikely.
- Relevance gate: this change passes — it modifies a spec-level requirement of `flutter-version-update` (the resolution rule for `buildTools.version` is in the spec at `openspec/specs/flutter-version-update/spec.md:30-48`, not just an implementation detail). A CI engineer reviewing the upgrade PR observes a different invariant: "the pinned build-tools matches what AGP asks for at runtime", not "the pinned build-tools matches the first packages.txt entry". The behavior change is externally observable as the absence of runtime SDK downloads during smoke tests.
