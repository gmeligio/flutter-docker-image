## 1. Pre-flight verification

- [ ] 1.1 Confirm via `rg latest_android_sdk_build_tools` that `script/latest_android_sdk_build_tools.sh` has zero callers in workflows, scripts, and docs
- [ ] 1.2 Confirm via `rg BUILD_TOOLS_VERSION` that the env var is referenced only at `script/updateAndroidVersions.gradle.kts:16-17` and `.github/workflows/update_version.yml:313`
- [ ] 1.3 Locally reproduce the AGP-default resolution: run `flutter create test_app` against Flutter 3.44.0, append the (modified) `updateAndroidVersions.gradle.kts` to `app/build.gradle.kts`, run `./gradlew updateAndroidVersions`, and confirm the emitted JSON's `buildTools.version == "36.0.0"`
- [ ] 1.4 Repeat 1.3 against Flutter 3.41.9 (current pinned version) and record the emitted value; if it differs from the committed `35.0.0`, capture the finding in the design "Open Questions" before proceeding

## 2. Gradle script change

- [ ] 2.1 In `script/updateAndroidVersions.gradle.kts`, replace the `System.getenv("BUILD_TOOLS_VERSION")` read with a read from the AGP DSL extension: `extensions.getByType(com.android.build.api.dsl.ApplicationExtension::class.java).buildToolsVersion`
- [ ] 2.2 Remove the `?: error("BUILD_TOOLS_VERSION env var is required")` fallback; the AGP read cannot return null for a configured app module — if AGP somehow returns null, error out with a message naming AGP, not the env var
- [ ] 2.3 Run the task locally (per task 1.3) to confirm the emitted JSON shape is unchanged apart from the `buildTools.version` value

## 3. Workflow change

- [ ] 3.1 In `.github/workflows/update_version.yml`, delete the "Update Android SDK build tools version" step (lines ~291-296: the `id: build_tools` step that does `curl … packages.txt | awk …`)
- [ ] 3.2 In the same workflow, delete the `BUILD_TOOLS_VERSION: ${{ steps.build_tools.outputs.build_tools_version }}` env mapping (line ~313) from the "Update default Android platform versions in Flutter" step
- [ ] 3.3 Spot-check that no other step in `update_version.yml` references `steps.build_tools.outputs.build_tools_version` or `env.BUILD_TOOLS_VERSION`

## 4. Cleanup

- [ ] 4.1 Delete `script/latest_android_sdk_build_tools.sh` (vestigial, zero callers per task 1.1)
- [ ] 4.2 Repo-wide grep for any markdown/docs mention of `packages.txt`-based build-tools resolution; update or remove

## 5. Bundled unblock of Flutter 3.44.0 upgrade (optional, do only if landing this together with the in-flight upgrade PR)

- [ ] 5.1 In `config/version.json`, set `android.buildTools.version` to `36.0.0` (the value the AGP read produces for Flutter 3.44.0)
- [ ] 5.2 In `test/android.yml`, set the "Android SDK build tools is pinned" `expectedOutput` to `36.0.0`
- [ ] 5.3 Confirm `cue vet config/schema.cue -d '#Version' config/version.json` passes

## 6. Verification

- [ ] 6.1 Run `./script/update_test.sh` (or equivalent) locally to regenerate any CUE-derived test fixtures
- [ ] 6.2 Push branch; confirm `build.yml` smoke tests (`test_image` for Android) pass — in particular, the "Gradle, licenses and platforms are already downloaded" test
- [ ] 6.3 Confirm `validate_config_version` (and any per-producer cue-vet step) passes on the resulting `config/version.json`
- [ ] 6.4 Manually trigger `update_version.yml` (workflow_dispatch) against `main` after merge and confirm the next monthly upgrade PR's diff shows no `BUILD_TOOLS_VERSION` env var, no `packages.txt` fetch, and a `buildTools.version` matching the AGP-resolved value
