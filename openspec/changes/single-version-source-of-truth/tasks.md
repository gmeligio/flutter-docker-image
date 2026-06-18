## 1. `update-flutter-version` → resolve + output (no file, no artifact)

- [ ] 1.1 Remove the top-level `env: FLUTTER_VERSION_PATH: config/flutter_version.json` (unused after this change).
- [ ] 1.2 Read the current pinned version from `config/version.json`: `old_version=$(jq -r '.flutter.version' config/version.json)`. Keep the upstream resolution unchanged.
- [ ] 1.3 On a bump, overlay the new block into the in-job manifest (`jq '.flutter = {channel,commit,version}'`) and set `changed=true`; emit outputs `flutter_channel` / `flutter_commit` / `flutter_version`. On no change, set `changed=false` and stop. (Keep an output name the gate `if:` conditions read — replace `new_version` usages with `changed` consistently, or keep `new_version` as the boolean.)
- [ ] 1.4 Validate the in-job manifest before finishing: `cue vet config/schema.cue -d '#Version' config/version.json` (only when changed). Remove the old standalone `-d '#FlutterVersion'` validation and the `upload-artifact` step entirely — no Flutter artifact is produced.

## 2. `update-windows-version` → output `windows_block`

- [ ] 2.1 Delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps (the Windows job never used the Flutter data).
- [ ] 2.2 Keep the windows resolution, release-identity check, in-job overlay into `config/version.json`, and `cue vet -d '#Version'` unchanged.
- [ ] 2.3 Replace the `Stage windows-only artifact` + `upload-artifact` steps with a job output: `windows_block=$(jq -c '{windows}' config/version.json)` written to `$GITHUB_OUTPUT` when the release-identity check matched; leave the output unset/empty otherwise. Keep `windows_skipped` (true when no block was produced). Keep the `vs-manifests` forensic upload as-is.

## 3. `update-android-version` → output `android_block`, stop shipping `android.yml`

- [ ] 3.1 Delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps.
- [ ] 3.2 Replace the `Export FLUTTER_* environment variables` step to read the resolver outputs: `FLUTTER_VERSION=${{ needs.update-flutter-version.outputs.flutter_version }}` and `FLUTTER_CHANNEL=...flutter_channel` into `$GITHUB_ENV`.
- [ ] 3.3 Keep `flutter create`, Gradle `updateAndroidVersions`, and `updateFastlaneVersion.js` (which write the `android` + `fastlane` blocks into `config/version.json`) unchanged. Keep the `cue vet -d '#Version'` self-validation.
- [ ] 3.4 Remove the `Generate test files with CUE` (`update_test.sh`) step and the `android.yml` `upload-artifact` step — `test/android.yml` is regenerated downstream from the composed manifest.
- [ ] 3.5 Replace the `Stage android-only fragment` + `upload-artifact` steps with a job output: `android_block=$(jq -c '{android, fastlane}' config/version.json)` to `$GITHUB_OUTPUT`. Keep `android_skipped` (true when no block was produced).

## 4. Collapse compose + validate + PR into `compose-and-open-pr`

- [ ] 4.1 Delete the `compose-version-manifest` and `validate-config-version` jobs.
- [ ] 4.2 Rename `update-docs-and-create-pr` → `compose-and-open-pr`. Set `needs: [update-flutter-version, update-android-version, update-windows-version]` and `if: !cancelled() && needs.update-flutter-version.outputs.<changed> == 'true'`. Keep the base checkout with `fetch-depth: 0` and `fetch-tags: true`.
- [ ] 4.3 Add a `Compose manifest` step that overlays the platform blocks onto the checked-out `config/version.json`, reading them from `env:` (never inline `${{ }}` into the script body): `jq --arg ... '.flutter = {...}'` (unconditional); `[ -n "$ANDROID_BLOCK" ] && jq --argjson a "$ANDROID_BLOCK" '. + $a' ...`; `[ -n "$WINDOWS_BLOCK" ] && jq --argjson w "$WINDOWS_BLOCK" '. + $w' ...`. Bind `ANDROID_BLOCK`/`WINDOWS_BLOCK` to the producer outputs and the `FLUTTER_*` to the resolver outputs.
- [ ] 4.4 Add a `Regenerate test/android.yml` step: `./script/update_test.sh` (runs against the composed `config/version.json`, with the base `test/android.yml` from checkout as structural input).
- [ ] 4.5 Add the central validation gate as a step *before* any PR work: `cue vet config/schema.cue -d '#Version' config/version.json`.
- [ ] 4.6 Keep the remaining steps (`setEnvironmentVariables.js`, `mise run docs`, commit-message/PR-body composition with the `*_skipped` annotations, `git-cliff` changelog, `create-pull-request`). Remove every `download-artifact` of a version/`android.yml` fragment and the `rm config/version.json test/android.yml` "can't overwrite" workaround — the job now mutates the checked-out files directly.

## 5. Fix `build.yml`

- [ ] 5.1 In `validate-version-files`, run only `cue vet config/schema.cue -d '#Version' config/version.json`; remove the `-d '#FlutterVersion' config/flutter_version.json` line; note in a comment that `#Version` embeds `#FlutterVersion`.

## 6. Remove the duplicate file and dead script

- [ ] 6.1 `git rm config/flutter_version.json`.
- [ ] 6.2 `git rm script/copyFlutterVersion.js` (dead; verify with a repo-wide grep for `copyFlutterVersion`).

## 7. Verify

- [ ] 7.1 Repo-wide grep: no live references to `flutter_version.json`, `FLUTTER_VERSION_PATH`, `copyFlutterVersion`, or any removed artifact name (`version.json.android`, `version.json.windows`, `flutter_version.json`, `composed-manifest`) outside `openspec/changes/archive/`.
- [ ] 7.2 YAML-parse `update-version.yml` and `build.yml`; confirm every `needs.*.outputs.*` reference resolves to a defined output and every `needs:` lists an existing job.
- [ ] 7.3 Local checks against committed `config/version.json`: the overlay chain (`jq --arg` flutter, `jq --argjson` android/windows) preserves sibling blocks; `jq -c '{android, fastlane}'` and `jq -c '{windows}'` yield valid block JSON; `script/update_test.sh` regenerates `test/android.yml` with no diff.
- [ ] 7.4 `workflow_dispatch` (or scheduled) end-to-end: the opened PR's `config/version.json` and `test/android.yml` are byte-equivalent to today's happy-path output, the diff has **no** deletion of `config/flutter_version.json`, and the PR's `build.yml` `validate-version-files` check passes. Spot-check an Android-skip / Windows-skip cycle: base block + regenerated `android.yml` carry forward and the PR-body annotation appears.
