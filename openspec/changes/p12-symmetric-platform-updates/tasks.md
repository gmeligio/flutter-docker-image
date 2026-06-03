## 1. Refactor `update-android-version` to emit a fragment

- [x] 1.1 Remove the "Copy Flutter version into version manifest and export FLUTTER_* environment variables" step's *file-mutation* responsibility from `update-android-version`. The step (calling `script/copyFlutterVersion.js`) currently both merges the Flutter block into `config/version.json` and exports env vars. In `update-android-version`, we want it to *not* mutate `config/version.json`. Two options: (a) stop calling the script here entirely and let the Android-specific logic write directly to the android block; or (b) keep the call for env-var export but throw away the file mutation. Choose option (a): the env vars `FLUTTER_VERSION` / `FLUTTER_CHANNEL` are still needed in `update-android-version` (used by `Setup Flutter` and `Update default Android platform versions in Flutter` steps), so replace the script call with a small inline step that reads from `config/flutter_version.json` and `core.exportVariable` only.
- [x] 1.2 After all the Android-specific updates run, produce a fragment artifact that contains the `android` **and** `fastlane` blocks — both are written by this job (`updateFastlaneVersion.js` writes `fastlane`; the Gradle step writes `android`), and `#Version` requires `fastlane!`. Use `jq '{android, fastlane}'` to extract from the in-job `config/version.json` and write to `${RUNNER_TEMP}/version.json.android`. **Rationale:** fastlane is owned by the Android producer because it is derived from the same Flutter-tag-driven run as the Android tooling; emitting `{android}` only would silently carry forward the base-branch `fastlane` block and a fastlane bump would never land even on a successful Android run.
- [x] 1.3 Validate the fragment before upload. Note that `config/schema.cue` has **no `#Android` definition** (only `#WindowsToolchain`, `#FlutterVersion`, `#Version`), so the fragment cannot be validated in isolation. Validate the full in-job `config/version.json` with `cue vet config/schema.cue -d '#Version' config/version.json` — the android+fastlane blocks were overlaid onto the schema-valid base, so a passing `#Version` check confirms this producer's blocks are well-formed.
- [x] 1.4 Change the upload step to upload `version.json.android` (the fragment) instead of `version.json`. Update the artifact name from `version.json` to `version.json.android` to match the file name and disambiguate from any consumer expecting the legacy name.
- [x] 1.5 Add an `android_skipped` job output set to `'true'` when the upload step did not run (job failed before reaching it) and `'false'` otherwise. Use `steps.upload-version.outcome` to detect this.
- [x] 1.6 Keep the `test/android.yml` artifact upload exactly as-is. It is a separate artifact, consumed independently by `compose-version-manifest`.

## 2. Refactor `update-windows-version` artifact name and validation

- [x] 2.1 No semantic change to the Windows job, but rename the fragment file from `version.json.windows` to keep symmetry with the new Android naming. Confirm: the file is already named `version.json.windows`. No rename needed; just confirm.
- [x] 2.2 Confirm the existing `windows_skipped` output (introduced by `p11`) is set in all skip paths. The current derived expression `steps.release_identity.outputs.matched != 'true' && 'true' || 'false'` already evaluates to `'true'` both on an explicit release-identity mismatch *and* when the job fails before `release_identity` runs (empty output → `!= 'true'` → `'true'`). The remaining gap is the case where identity matched (`matched == 'true'`) but a *later* step failed before upload — there the expression yields `'false'` despite no fragment being produced. Tighten the output so it is `'true'` whenever the upload step did not run (analogous to task 1.5, e.g. gate on `steps.upload-version.outcome`).

## 3. Add `compose-version-manifest` job

- [x] 3.1 In `.github/workflows/update-version.yml`, add a new job `compose-version-manifest` between the platform-updater jobs and `validate-config-version`. Its `needs:` is `[update-flutter-version, update-android-version, update-windows-version]` and its `if:` is `!cancelled() && needs.update-flutter-version.result == 'success'`. Runs on `ubuntu-24.04` with a `harden-runner` step.
- [x] 3.2 Checkout the base branch to obtain the schema-valid `config/version.json` and `test/android.yml` as the composition canvas.
- [x] 3.3 Download Flutter's artifact (`needs.update-flutter-version.outputs.flutter_version_artifact_id`) — always required.
- [x] 3.4 Conditionally download Android's fragment artifact when `needs.update-android-version.outputs.version_artifact_id` is non-empty. Use a "Compose artifact id list" pattern (like the one introduced in `p11`'s PR job) to assemble the `artifact-ids` input dynamically.
- [x] 3.5 Conditionally download Windows's fragment artifact when `needs.update-windows-version.outputs.version_artifact_id` is non-empty.
- [x] 3.6 Conditionally download Android's `test/android.yml` artifact when Android produced it; otherwise use the base-branch checkout's copy.
- [x] 3.7 Overlay the Flutter block onto the base `config/version.json` via `jq -s '.[0] * .[1]' config/version.json config/flutter_version.json > tmp && mv tmp config/version.json` (or use `script/copyFlutterVersion.js` — decide based on whether the script's env-var export is wanted here; in this job, only the file mutation is wanted, so prefer the inline `jq`).
- [x] 3.8 Overlay the Android **and fastlane** blocks if the Android fragment was downloaded: `jq -s '.[0] + {android: .[1].android, fastlane: .[1].fastlane}' config/version.json config/version.json.android > tmp && mv tmp config/version.json`. (The Android fragment carries both per task 1.2; if Android skipped, both blocks carry forward from the base manifest.)
- [x] 3.9 Overlay the Windows block if downloaded: `jq -s '.[0] + {windows: .[1].windows}' config/version.json config/version.json.windows > tmp && mv tmp config/version.json`.
- [x] 3.10 Clean up the fragment files from the composed-manifest staging area so they don't get uploaded with the composed artifact.
- [x] 3.11 Upload the composed `config/version.json` (and `test/android.yml`) as a single `composed-manifest` artifact. Expose its artifact id as a job output `composed_artifact_id`.

## 4. Point `validate-config-version` at the composed artifact

- [x] 4.1 Change `validate-config-version.needs` from `update-android-version` to `compose-version-manifest`.
- [x] 4.2 Change the artifact id reference from `needs.update-android-version.outputs.version_artifact_id` to `needs.compose-version-manifest.outputs.composed_artifact_id`.
- [x] 4.3 Confirm `validate-config-version` still runs `cue vet config/schema.cue -d '#Version' config/version.json` and exits 0 only on the composed (final) manifest.

## 5. Simplify `update-docs-and-create-pr` to be a read-only consumer

- [x] 5.1 Change the PR job's `needs:` to `[update-flutter-version, update-android-version, update-windows-version, compose-version-manifest, validate-config-version]`. Keep platform updaters in `needs:` so `<platform>_skipped` outputs remain accessible for PR-body annotation; the actual data consumed is `composed-manifest`.
- [x] 5.2 Replace the "Download configuration artifacts" + "Compose artifact id list" + "Merge windows block" steps with a single "Download composed manifest" step that fetches `needs.compose-version-manifest.outputs.composed_artifact_id` into the working directory.
- [x] 5.3 Remove the now-unused "Validate merged version.json with CUE" step. Validation lives in `validate-config-version` only.
- [x] 5.4 Remove the "Download test artifacts" step (the composed-manifest artifact now carries `test/android.yml`).
- [x] 5.5 Update the "Compose PR body" step to annotate both platforms uniformly: when `needs.update-android-version.outputs.android_skipped == 'true'`, add the "Android toolchain unchanged this cycle" line; same for Windows. Keep the existing job-log URL pattern.
- [x] 5.6 Confirm `script/setEnvironmentVariables.js` and `script/copyFlutterVersion.js` (for env-var export only, not file mutation) still work against the composed manifest. The env-var exports happen against `config/version.json` which is now the composed result.

## 6. Validate

- [ ] 6.1 Run `openspec validate p12-symmetric-platform-updates --strict`.
- [ ] 6.2 Verify `.github/workflows/update-version.yml` parses cleanly via `python3 -c "import yaml; yaml.safe_load(open(…))"`.
- [ ] 6.3 In the implementation PR description, document the manual verification matrix:
  - **Happy path**: `workflow_dispatch` after merging — confirm both platforms produce fragments, composed manifest is correct, PR opens without skip annotations.
  - **Android-skipped path**: temporarily set `update-android-version.if: false` on the PR branch and dispatch — confirm composed manifest has new flutter + new windows + carried-forward android; PR body shows Android annotation.
  - **Windows-skipped path**: same as above for `update-windows-version.if: false` — confirm composed manifest has new flutter + new android + carried-forward windows; PR body shows Windows annotation.
  - **Both-skipped path**: both jobs `if: false` — confirm composed manifest has only new flutter, both blocks carried forward, PR body has both annotations.

## 7. Spec validation against archived p11

- [ ] 7.1 After `p11-resilient-windows-update` is archived (post-merge), confirm `openspec validate p12-symmetric-platform-updates --strict` still passes against the archived spec state.
- [ ] 7.2 Update any cross-references in p12's design.md if archival paths change.
