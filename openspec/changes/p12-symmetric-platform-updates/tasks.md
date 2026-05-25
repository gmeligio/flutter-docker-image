## 1. Refactor `update_android_version` to emit a fragment

- [ ] 1.1 Remove the "Copy Flutter version into version manifest and export FLUTTER_* environment variables" step's *file-mutation* responsibility from `update_android_version`. The step (calling `script/copyFlutterVersion.js`) currently both merges the Flutter block into `config/version.json` and exports env vars. In `update_android_version`, we want it to *not* mutate `config/version.json`. Two options: (a) stop calling the script here entirely and let the Android-specific logic write directly to the android block; or (b) keep the call for env-var export but throw away the file mutation. Choose option (a): the env vars `FLUTTER_VERSION` / `FLUTTER_CHANNEL` are still needed in `update_android_version` (used by `Setup Flutter` and `Update default Android platform versions in Flutter` steps), so replace the script call with a small inline step that reads from `config/flutter_version.json` and `core.exportVariable` only.
- [ ] 1.2 After all the Android-specific updates run, produce a fragment artifact that contains only the `android` block. Use `jq '{android}'` to extract from the in-job `config/version.json` and write to `${RUNNER_TEMP}/version.json.android`.
- [ ] 1.3 Validate the fragment before upload: run `cue vet config/schema.cue -d '#Android' …` on it (requires a `#Android` definition in `config/schema.cue` — if one doesn't exist, validate the full in-job manifest with `#Version` instead, since the android block was overlaid onto the schema-valid base).
- [ ] 1.4 Change the upload step to upload `version.json.android` (the fragment) instead of `version.json`. Update the artifact name from `version.json` to `version.json.android` to match the file name and disambiguate from any consumer expecting the legacy name.
- [ ] 1.5 Add an `android_skipped` job output set to `'true'` when the upload step did not run (job failed before reaching it) and `'false'` otherwise. Use `steps.upload-version.outcome` to detect this.
- [ ] 1.6 Keep the `test/android.yml` artifact upload exactly as-is. It is a separate artifact, consumed independently by `compose_version_manifest`.

## 2. Refactor `update_windows_version` artifact name and validation

- [ ] 2.1 No semantic change to the Windows job, but rename the fragment file from `version.json.windows` to keep symmetry with the new Android naming. Confirm: the file is already named `version.json.windows`. No rename needed; just confirm.
- [ ] 2.2 Confirm the existing `windows_skipped` output (introduced by `p11`) is set in all skip paths (release-identity mismatch, plus any future natural failures). The current implementation only sets it on release-identity mismatch; tighten it to also be `'true'` when the upload step did not run (analogous to task 1.5).

## 3. Add `compose_version_manifest` job

- [ ] 3.1 In `.github/workflows/update_version.yml`, add a new job `compose_version_manifest` between the platform-updater jobs and `validate_config_version`. Its `needs:` is `[update_flutter_version, update_android_version, update_windows_version]` and its `if:` is `!cancelled() && needs.update_flutter_version.result == 'success'`. Runs on `ubuntu-24.04` with a `harden-runner` step.
- [ ] 3.2 Checkout the base branch to obtain the schema-valid `config/version.json` and `test/android.yml` as the composition canvas.
- [ ] 3.3 Download Flutter's artifact (`needs.update_flutter_version.outputs.flutter_version_artifact_id`) — always required.
- [ ] 3.4 Conditionally download Android's fragment artifact when `needs.update_android_version.outputs.version_artifact_id` is non-empty. Use a "Compose artifact id list" pattern (like the one introduced in `p11`'s PR job) to assemble the `artifact-ids` input dynamically.
- [ ] 3.5 Conditionally download Windows's fragment artifact when `needs.update_windows_version.outputs.version_artifact_id` is non-empty.
- [ ] 3.6 Conditionally download Android's `test/android.yml` artifact when Android produced it; otherwise use the base-branch checkout's copy.
- [ ] 3.7 Overlay the Flutter block onto the base `config/version.json` via `jq -s '.[0] * .[1]' config/version.json config/flutter_version.json > tmp && mv tmp config/version.json` (or use `script/copyFlutterVersion.js` — decide based on whether the script's env-var export is wanted here; in this job, only the file mutation is wanted, so prefer the inline `jq`).
- [ ] 3.8 Overlay the Android block if downloaded: `jq -s '.[0] + {android: .[1].android}' config/version.json config/version.json.android > tmp && mv tmp config/version.json`.
- [ ] 3.9 Overlay the Windows block if downloaded: `jq -s '.[0] + {windows: .[1].windows}' config/version.json config/version.json.windows > tmp && mv tmp config/version.json`.
- [ ] 3.10 Clean up the fragment files from the composed-manifest staging area so they don't get uploaded with the composed artifact.
- [ ] 3.11 Upload the composed `config/version.json` (and `test/android.yml`) as a single `composed-manifest` artifact. Expose its artifact id as a job output `composed_artifact_id`.

## 4. Point `validate_config_version` at the composed artifact

- [ ] 4.1 Change `validate_config_version.needs` from `update_android_version` to `compose_version_manifest`.
- [ ] 4.2 Change the artifact id reference from `needs.update_android_version.outputs.version_artifact_id` to `needs.compose_version_manifest.outputs.composed_artifact_id`.
- [ ] 4.3 Confirm `validate_config_version` still runs `cue vet config/schema.cue -d '#Version' config/version.json` and exits 0 only on the composed (final) manifest.

## 5. Simplify `update_docs_and_create_pr` to be a read-only consumer

- [ ] 5.1 Change the PR job's `needs:` to `[update_flutter_version, update_android_version, update_windows_version, compose_version_manifest, validate_config_version]`. Keep platform updaters in `needs:` so `<platform>_skipped` outputs remain accessible for PR-body annotation; the actual data consumed is `composed-manifest`.
- [ ] 5.2 Replace the "Download configuration artifacts" + "Compose artifact id list" + "Merge windows block" steps with a single "Download composed manifest" step that fetches `needs.compose_version_manifest.outputs.composed_artifact_id` into the working directory.
- [ ] 5.3 Remove the now-unused "Validate merged version.json with CUE" step. Validation lives in `validate_config_version` only.
- [ ] 5.4 Remove the "Download test artifacts" step (the composed-manifest artifact now carries `test/android.yml`).
- [ ] 5.5 Update the "Compose PR body" step to annotate both platforms uniformly: when `needs.update_android_version.outputs.android_skipped == 'true'`, add the "Android toolchain unchanged this cycle" line; same for Windows. Keep the existing job-log URL pattern.
- [ ] 5.6 Confirm `script/setEnvironmentVariables.js` and `script/copyFlutterVersion.js` (for env-var export only, not file mutation) still work against the composed manifest. The env-var exports happen against `config/version.json` which is now the composed result.

## 6. Validate

- [ ] 6.1 Run `openspec validate p12-symmetric-platform-updates --strict`.
- [ ] 6.2 Verify `.github/workflows/update_version.yml` parses cleanly via `python3 -c "import yaml; yaml.safe_load(open(…))"`.
- [ ] 6.3 In the implementation PR description, document the manual verification matrix:
  - **Happy path**: `workflow_dispatch` after merging — confirm both platforms produce fragments, composed manifest is correct, PR opens without skip annotations.
  - **Android-skipped path**: temporarily set `update_android_version.if: false` on the PR branch and dispatch — confirm composed manifest has new flutter + new windows + carried-forward android; PR body shows Android annotation.
  - **Windows-skipped path**: same as above for `update_windows_version.if: false` — confirm composed manifest has new flutter + new android + carried-forward windows; PR body shows Windows annotation.
  - **Both-skipped path**: both jobs `if: false` — confirm composed manifest has only new flutter, both blocks carried forward, PR body has both annotations.

## 7. Spec validation against archived p11

- [ ] 7.1 After `p11-resilient-windows-update` is archived (post-merge), confirm `openspec validate p12-symmetric-platform-updates --strict` still passes against the archived spec state.
- [ ] 7.2 Update any cross-references in p12's design.md if archival paths change.
