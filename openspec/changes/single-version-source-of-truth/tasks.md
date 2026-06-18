## 1. Make `update-flutter-version` a `{flutter}` fragment producer

- [ ] 1.1 In `.github/workflows/update-version.yml`, remove the top-level `env: FLUTTER_VERSION_PATH: config/flutter_version.json` (no longer referenced after this change).
- [ ] 1.2 In the `update-flutter-version` "resolve" step, read the current pinned version from `config/version.json`: `old_version=$(jq -r '.flutter.version' config/version.json)`. Keep the upstream resolution (`releases_linux.json`, `max_by(.release_date)`) unchanged.
- [ ] 1.3 On a bump (`old_version != new_version`), overlay the new block into the in-job manifest: `jq --arg channel "$new_channel" --arg commit "$new_commit" --arg version "$new_version" '.flutter = {channel: $channel, commit: $commit, version: $version}' config/version.json > config/version.json.tmp && mv config/version.json.tmp config/version.json`. Set `result=true`. On no change, set `result=false` and skip the rest.
- [ ] 1.4 Add job outputs `flutter_version` and `flutter_channel` (the resolved scalars) for `update-android-version`'s mid-pipeline consumption. Keep `new_version` as the boolean gate output. Replace the old `flutter_version_artifact_id` output binding to point at the new fragment upload step (task 1.6).
- [ ] 1.5 Validate the full in-job manifest before staging the fragment: `cue vet config/schema.cue -d '#Version' config/version.json` (symmetric with the Android/Windows producers). Run only when `result == 'true'`.
- [ ] 1.6 Stage and upload the fragment: `jq '{flutter}' config/version.json > "${RUNNER_TEMP}/version.json.flutter"`, then upload it as artifact name `version.json.flutter` with `id: upload-version`. Bind `flutter_version_artifact_id: ${{ steps.upload-version.outputs.artifact-id }}` (keep the existing output name so `compose-version-manifest` wiring stays minimal).

## 2. Drop the old-file dance from the platform updaters

- [ ] 2.1 In `update-windows-version`, delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps — the Windows job never used the Flutter data (it was downloaded "for symmetry" only). No other Windows logic changes.
- [ ] 2.2 In `update-android-version`, delete the `Delete flutter_version.json` (`rm`) and `Download artifact with the new Flutter version` steps.
- [ ] 2.3 In `update-android-version`, replace the `Export FLUTTER_* environment variables` step (which read `flutter_version.json` via `jq`) with one that reads the resolver outputs: `echo "FLUTTER_VERSION=${{ needs.update-flutter-version.outputs.flutter_version }}" >> "$GITHUB_ENV"` and likewise `FLUTTER_CHANNEL=...flutter_channel`. Confirm `update-android-version`'s `needs:` includes `update-flutter-version` (it does).
- [ ] 2.4 Update the `Setup mise tools` comment in `update-android-version` to reflect that `jq`/`cue` are still needed for the `Stage android-only fragment` and `Validate` steps (no longer for an env-export `jq`).

## 3. Overlay the Flutter fragment symmetrically in `compose-version-manifest`

- [ ] 3.1 Delete the `Delete flutter_version.json` (`rm`) step in `compose-version-manifest`.
- [ ] 3.2 Replace the standalone `Download Flutter fragment` step so the Flutter fragment id is included in the existing dynamic artifact-id list (prepend `needs.update-flutter-version.outputs.flutter_version_artifact_id` to the list built in `Compose fragment artifact id list`), and download all fragments together with `merge-multiple: true` into `${RUNNER_TEMP}/fragments`. Distinct filenames (`version.json.flutter`, `version.json.android`, `version.json.windows`) keep the merge safe.
- [ ] 3.3 In the `Compose manifest` step, replace the old `jq -s '.[0] * .[1]' config/version.json config/flutter_version.json` + `rm config/flutter_version.json` with an overlay from the Flutter fragment: `jq -s '.[0] + {flutter: .[1].flutter}' config/version.json "${FRAGMENTS}/version.json.flutter" > config/version.json.tmp && mv config/version.json.tmp config/version.json`. Keep this overlay unconditional (Flutter always produces a fragment when the pipeline runs); keep the Android/Windows overlays guarded by file presence, unchanged.
- [ ] 3.4 Update the `compose-version-manifest` header comment so it no longer says "without its fragment the compose deletes the base file and jq fails on the gap" — the Flutter overlay now reads a fragment like the others.

## 4. Update `update-docs-and-create-pr`

- [ ] 4.1 In the `Delete ... and android.yml` step, remove `config/flutter_version.json` from the `rm` list (it no longer exists in the checkout); delete only `config/version.json test/android.yml` before downloading the composed manifest.

## 5. Fix `build.yml` validation

- [ ] 5.1 In `.github/workflows/build.yml`, change the `validate-version-files` job's CUE step to run only `cue vet config/schema.cue -d '#Version' config/version.json`. Remove the `-d '#FlutterVersion' config/flutter_version.json` line. Update the step name/comment to note `#Version` embeds `#FlutterVersion`.

## 6. Remove the duplicate file and dead script

- [ ] 6.1 `git rm config/flutter_version.json`.
- [ ] 6.2 `git rm script/copyFlutterVersion.js` (dead — no workflow references it; verify with a repo-wide grep for `copyFlutterVersion`).

## 7. Verify

- [ ] 7.1 Repo-wide grep confirms no live references remain to `flutter_version.json`, `FLUTTER_VERSION_PATH`, or `copyFlutterVersion` (outside `openspec/changes/archive/`).
- [ ] 7.2 YAML-parse `update-version.yml` and `build.yml`; confirm every `needs.update-flutter-version.outputs.*` reference resolves to a defined output.
- [ ] 7.3 Local manifest-shape checks: `jq '{flutter}' config/version.json` yields a `{flutter:{channel,commit,version}}` doc; the compose overlay `jq -s '.[0] + {flutter: .[1].flutter}'` preserves `android`, `fastlane`, and `windows`.
- [ ] 7.4 Trigger a `workflow_dispatch` run of `update-version.yml` (or await the next scheduled run): the opened PR's `config/version.json` is byte-equivalent to today's happy-path output, its diff contains **no** deletion of `config/flutter_version.json`, and the PR's `build.yml` `validate-version-files` check passes.
