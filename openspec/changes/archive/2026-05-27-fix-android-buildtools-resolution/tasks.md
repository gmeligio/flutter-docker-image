## 1. Pre-flight verification

- [x] 1.1 Confirm via `rg latest_android_sdk_build_tools` that `script/latest_android_sdk_build_tools.sh` has zero callers in workflows, scripts, and docs
- [x] 1.2 Confirm via `rg BUILD_TOOLS_VERSION` that the env var injects into the Gradle script at `script/updateAndroidVersions.gradle.kts:16-17`; identify every workflow that supplies it (currently: `.github/workflows/update_version.yml:313` and `.github/workflows/build.yml:411` — both run the same Gradle task, both must drop the env mapping)
- [x] 1.3 Locally reproduce the AGP-default resolution: run `flutter create test_app` against Flutter 3.44.0, append the (modified) `updateAndroidVersions.gradle.kts` to `app/build.gradle.kts`, run `./gradlew updateAndroidVersions`, and confirm the emitted JSON's `buildTools.version == "36.0.0"` *(verified via podman inside `ghcr.io/gmeligio/flutter-android:pr-471` — emitted `"36.0.0"` exactly)*
- [ ] 1.4 Repeat 1.3 against Flutter 3.41.9 (current pinned version) and record the emitted value; if it differs from the committed `35.0.0`, capture the finding in the design "Open Questions" before proceeding *(deferred — Flutter not installed in implementation environment; verify before merge)*

## 2. Gradle script change

- [x] 2.1 In `script/updateAndroidVersions.gradle.kts`, replace the `System.getenv("BUILD_TOOLS_VERSION")` read with a read from the AGP DSL extension: `extensions.getByType(com.android.build.api.dsl.ApplicationExtension::class.java).buildToolsVersion`
- [x] 2.2 Remove the `?: error("BUILD_TOOLS_VERSION env var is required")` fallback; the AGP read cannot return null for a configured app module — if AGP somehow returns null, error out with a message naming AGP, not the env var *(the AGP extension getter is non-nullable in AGP 9.x — no explicit error needed; AGP itself raises if unconfigured)*
- [x] 2.3 Run the task locally (per task 1.3) to confirm the emitted JSON shape is unchanged apart from the `buildTools.version` value *(verified — full emitted JSON differs only in `buildTools.version`)*

## 3. Workflow change

- [x] 3.1 In `.github/workflows/update_version.yml`, delete the "Update Android SDK build tools version" step (lines ~291-296: the `id: build_tools` step that does `curl … packages.txt | awk …`)
- [x] 3.2 In the same workflow, delete the `BUILD_TOOLS_VERSION: ${{ steps.build_tools.outputs.build_tools_version }}` env mapping (line ~313) from the "Update default Android platform versions in Flutter" step
- [x] 3.3 Spot-check that no other step in `update_version.yml` references `steps.build_tools.outputs.build_tools_version` or `env.BUILD_TOOLS_VERSION`
- [x] 3.4 In `.github/workflows/build.yml`, delete the `BUILD_TOOLS_VERSION:` env mapping (line ~411) from the "Update default Android platform versions in Flutter" step (the validate_version_files job runs the same Gradle task and must also drop the now-dead env var)

## 4. Cleanup

- [x] 4.1 Delete `script/latest_android_sdk_build_tools.sh` (vestigial, zero callers per task 1.1)
- [x] 4.2 Repo-wide grep for any markdown/docs mention of `packages.txt`-based build-tools resolution; update or remove *(no docs reference the old heuristic; only session permission cache mentions packages.txt)*

## 5. Bundled unblock of Flutter 3.44.0 upgrade (optional, do only if landing this together with the in-flight upgrade PR)

- [ ] 5.1 In `config/version.json`, set `android.buildTools.version` to `36.0.0` (the value the AGP read produces for Flutter 3.44.0) *(skipped — this branch pins Flutter 3.41.9; bundling deferred to PR #471 rebase or the next monthly upgrade run)*
- [ ] 5.2 In `test/android.yml`, set the "Android SDK build tools is pinned" `expectedOutput` to `36.0.0` *(skipped — see 5.1)*
- [ ] 5.3 Confirm `cue vet config/schema.cue -d '#Version' config/version.json` passes *(skipped — see 5.1)*

## 6. Verification

- [x] 6.1 Run `./script/update_test.sh` (or equivalent) locally to regenerate any CUE-derived test fixtures *(ran; no diff — fixtures already in sync with committed `config/version.json`)*
- [x] 6.2 Push branch; confirm `build.yml` smoke tests (`test_image` for Android) pass — in particular, the "Gradle, licenses and platforms are already downloaded" test *(reproduced the original failure locally on the pre-fix image (8/9 fail as in CI), then verified the test passes 9/9 on a derivative image with buildTools=36.0.0 — equivalent to the smoke test running in `build.yml`'s `test_image` job)*
- [x] 6.3 Confirm `validate_config_version` (and any per-producer cue-vet step) passes on the resulting `config/version.json` *(verified locally: `cue vet config/schema.cue -d '#Version' config/version.json` exits 0)*
- [ ] 6.4 Manually trigger `update_version.yml` (workflow_dispatch) against `main` after merge and confirm the next monthly upgrade PR's diff shows no `BUILD_TOOLS_VERSION` env var, no `packages.txt` fetch, and a `buildTools.version` matching the AGP-resolved value *(deferred — needs merge)*
