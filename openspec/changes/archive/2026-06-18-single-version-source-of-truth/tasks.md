## 1. `update-flutter-version` → resolve + output (no file, no artifact)

- [x] 1.1 Remove the top-level `env: FLUTTER_VERSION_PATH: config/flutter_version.json` (unused after this change).
- [x] 1.2 Read the current pinned version from `config/version.json`: `old_version=$(jq -r '.flutter.version' config/version.json)`. Keep the upstream resolution unchanged.
- [x] 1.3 On a bump, overlay the new block into the in-job manifest (`jq '.flutter = {channel,commit,version}'`) and set `changed=true`; emit outputs `flutter_channel` / `flutter_commit` / `flutter_version`. On no change, set `changed=false` and stop. (Keep an output name the gate `if:` conditions read — replace `new_version` usages with `changed` consistently, or keep `new_version` as the boolean.)
- [x] 1.4 Validate the in-job manifest before finishing: `cue vet config/schema.cue -d '#Version' config/version.json` (only when changed). Remove the old standalone `-d '#FlutterVersion'` validation and the `upload-artifact` step entirely — no Flutter artifact is produced.

## 2. `update-windows-version` → output `windows_block`

- [x] 2.1 Delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps (the Windows job never used the Flutter data).
- [x] 2.2 Keep the windows resolution, release-identity check, in-job overlay into `config/version.json`, and `cue vet -d '#Version'` unchanged.
- [x] 2.3 Replace the `Stage windows-only artifact` + `upload-artifact` steps with a job output: `windows_block=$(jq -c '{windows}' config/version.json)` written to `$GITHUB_OUTPUT` when the release-identity check matched; leave the output unset/empty otherwise. Keep `windows_skipped` (true when no block was produced). Keep the `vs-manifests` forensic upload as-is.

## 3. `update-android-version` → output `android_block`, stop shipping `android.yml`

- [x] 3.1 Delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps.
- [x] 3.2 Replace the `Export FLUTTER_* environment variables` step to read the resolver outputs: `FLUTTER_VERSION=${{ needs.update-flutter-version.outputs.flutter_version }}` and `FLUTTER_CHANNEL=...flutter_channel` into `$GITHUB_ENV`.
- [x] 3.3 Keep `flutter create`, Gradle `updateAndroidVersions`, and `updateFastlaneVersion.js` (which write the `android` + `fastlane` blocks into `config/version.json`) unchanged. Keep the `cue vet -d '#Version'` self-validation.
- [x] 3.4 Remove the `Generate test files with CUE` (`update_test.sh`) step and the `android.yml` `upload-artifact` step — `test/android.yml` is regenerated downstream from the composed manifest.
- [x] 3.5 Replace the `Stage android-only fragment` + `upload-artifact` steps with a job output: `android_block=$(jq -c '{android, fastlane}' config/version.json)` to `$GITHUB_OUTPUT`. Keep `android_skipped` (true when no block was produced).

## 4. Collapse compose + validate + PR into `compose-and-open-pr`

- [x] 4.1 Delete the `compose-version-manifest` and `validate-config-version` jobs.
- [x] 4.2 Rename `update-docs-and-create-pr` → `compose-and-open-pr`. Set `needs: [update-flutter-version, update-android-version, update-windows-version]` and `if: !cancelled() && needs.update-flutter-version.outputs.<changed> == 'true'`. Keep the base checkout with `fetch-depth: 0` and `fetch-tags: true`.
- [x] 4.3 Add a `Compose manifest` step that overlays the platform blocks onto the checked-out `config/version.json`, reading them from `env:` (never inline `${{ }}` into the script body): `jq --arg ... '.flutter = {...}'` (unconditional); `[ -n "$ANDROID_BLOCK" ] && jq --argjson a "$ANDROID_BLOCK" '. + $a' ...`; `[ -n "$WINDOWS_BLOCK" ] && jq --argjson w "$WINDOWS_BLOCK" '. + $w' ...`. Bind `ANDROID_BLOCK`/`WINDOWS_BLOCK` to the producer outputs and the `FLUTTER_*` to the resolver outputs.
- [x] 4.4 Add a `Regenerate test/android.yml` step: `./script/update_test.sh` (runs against the composed `config/version.json`, with the base `test/android.yml` from checkout as structural input).
- [x] 4.5 Add the central validation gate as a step *before* any PR work: `cue vet config/schema.cue -d '#Version' config/version.json`.
- [x] 4.6 Keep the remaining steps (`setEnvironmentVariables.js`, `mise run docs`, commit-message/PR-body composition with the `*_skipped` annotations, `git-cliff` changelog, `create-pull-request`). Remove every `download-artifact` of a version/`android.yml` fragment and the `rm config/version.json test/android.yml` "can't overwrite" workaround — the job now mutates the checked-out files directly.

## 5. Fix `build.yml`

- [x] 5.1 In `validate-version-files`, run only `cue vet config/schema.cue -d '#Version' config/version.json`; remove the `-d '#FlutterVersion' config/flutter_version.json` line; note in a comment that `#Version` embeds `#FlutterVersion`.

## 6. Remove the duplicate file and dead script

- [x] 6.1 `git rm config/flutter_version.json`.
- [x] 6.2 `git rm script/copyFlutterVersion.js` (dead; verify with a repo-wide grep for `copyFlutterVersion`).

## 7. Verify

- [x] 7.1 Repo-wide grep: no live references to `flutter_version.json`, `FLUTTER_VERSION_PATH`, `copyFlutterVersion`, or any removed artifact name (`version.json.android`, `version.json.windows`, `flutter_version.json`, `composed-manifest`) outside `openspec/changes/archive/`.
- [x] 7.2 YAML-parse `update-version.yml` and `build.yml`; confirm every `needs.*.outputs.*` reference resolves to a defined output and every `needs:` lists an existing job.
- [x] 7.3 Local checks against committed `config/version.json`: the overlay chain (`jq --arg` flutter, `jq --argjson` android/windows) preserves sibling blocks; `jq -c '{android, fastlane}'` and `jq -c '{windows}'` yield valid block JSON; `script/update_test.sh` regenerates `test/android.yml` with no diff.
- [x] 7.4 **Runtime gate — partially verified.** `workflow_dispatch` run #18 (`27747183863`) of `update-version.yml` on `main` (which pins 3.44.2, the latest stable) executed the new pipeline green: `update-flutter-version` resolved no change, and `update-windows-version` / `update-android-version` / `compose-and-open-pr` all skipped — the "No upstream change" scenario, with no `flutter_version.json` error. The happy-path (real bump → compose → regenerate `android.yml` → open PR) is covered by proxy (`build.yml`'s `Validate generated config` proves `update_test.sh` regenerates `test/android.yml` with zero drift; the `jq` overlay was simulated locally) and will be exercised end-to-end on the next genuine upstream Flutter release.
