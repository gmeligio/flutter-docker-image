## 1. Schema and validation fixes (independent, ship-able alone)

- [x] 1.1 In `config/schema.cue`, replace the dangling `#PatchVersion` reference inside `#FlutterVersion.flutter` with `#SemverPatch`.
- [x] 1.2 Confirm `config/schema.cue` already restricts `flutter.channel` to literal `"stable"` (no further change needed; verify only).
- [x] 1.3 Run `cue vet config/schema.cue -d '#FlutterVersion' config/flutter_version.json` locally — must exit 0.
- [x] 1.4 Run `cue vet config/schema.cue -d '#Version' config/version.json` locally — must exit 0.
- [x] 1.5 In `config/android.cue`, change the `commandTests` length guard from `if len(input.fileContentTests) >= 3` to `if len(input.commandTests) >= 3`.

## 2. Replace JS fetcher with CUE-driven step

- [x] 2.1 In `.github/workflows/update_version.yml`, delete the `Update latest Flutter version` step (the `actions/github-script` call to `script/updateFlutterVersion.js`).
- [x] 2.2 Rewrite the `Fetch and update latest Flutter version` step (id: `update_flutter_version`) to: (a) `curl` `releases_linux.json`; (b) `cue import` it; (c) read the on-disk old version via `cue export config/flutter_version.json --out json | jq -r .flutter.version` (or `cue eval` equivalent); (d) compute the latest stable version via `cue eval --concrete --expression '[for r in releases if r.channel == "stable" && (r.version =~ "^[0-9]+\\.[0-9]+\\.[0-9]+$") {r}][0]'` (verify shape during implementation); (e) compare; (f) only if different, run `cue eval --force --outfile config/flutter_version.json --concrete --expression ...` and `echo "result=true" >> $GITHUB_OUTPUT`; otherwise `echo "result=false" >> $GITHUB_OUTPUT`.
- [x] 2.3 Echo old version, new version, and verdict to the run log before writing `$GITHUB_OUTPUT`.
- [x] 2.4 Keep the existing `Validate version.json with CUE` and `Upload artifact with the new Flutter version` steps; verify their `if: steps.update_flutter_version.outputs.result == 'true'` gates still resolve correctly after step renames.
- [x] 2.5 Delete `script/updateFlutterVersion.js`.
- [x] 2.6 Search the repo for any remaining reference to `updateFlutterVersion.js` or `updateFlutterVersion` and remove it (none expected outside the workflow).

## 3. Wire build-tools sourcing from packages.txt

- [ ] 3.1 Read `script/update_test.sh` and `script/updateAndroidVersions.gradle.kts` to determine where `android_sdk_build_tools_version` is currently sourced and how it flows into `config/version.json`.
- [ ] 3.2 In `update_version.yml` job `update_android_version`, give the `Update Android SDK build tools version` step `id: build_tools` and write the extracted version to `$GITHUB_OUTPUT` (the script already does this; just add the `id`).
- [ ] 3.3 Replace the gradle-derived build-tools value in `script/update_test.sh` (or wherever it's consumed) with the `packages.txt`-sourced value from step 3.2 — exposed via env var or step-output reference.
- [ ] 3.4 If `updateAndroidVersions.gradle.kts` no longer needs to extract build-tools, simplify it; if other Android values still need gradle extraction, leave gradle alone and only swap the build-tools field.
- [ ] 3.5 Verify that the resulting `config/version.json` still passes `cue vet config/schema.cue -d '#Version'` (the `#SemverPatch` constraint will reject malformed extractions).

## 4. Fix the commit-message step

- [ ] 4.1 In `.github/workflows/update_version.yml` job `update_docs_and_create_pr`, change `Create commit message variable` to write `commit_message=...` to `$GITHUB_OUTPUT` instead of `$GITHUB_ENV`.
- [ ] 4.2 Echo the resolved commit message to the run log so an empty value is visible.
- [ ] 4.3 Confirm `peter-evans/create-pull-request` references resolve to the non-empty step output.

## 5. Cosmetic and stale cleanup

- [ ] 5.1 Remove the stray empty `#` comment line in the `permissions:` block of job `update_flutter_version` (above `contents: write`).
- [ ] 5.2 Verify no unreferenced env vars or step ids remain (e.g. orphan `COMMIT_MESSAGE` env, unused job outputs).

## 6. End-to-end verification before merge

- [ ] 6.1 Push branch and trigger `update_version.yml` via `workflow_dispatch`. Inspect logs to confirm: old/new version echo, verdict, and outcome (PR opened OR clean skip).
- [ ] 6.2 Manually rewind `config/flutter_version.json` on the branch to a known older version, push, re-trigger, and confirm an upgrade PR is opened with non-empty title and commit message.
- [ ] 6.3 Restore `config/flutter_version.json` to current.
- [ ] 6.4 Confirm `build.yml` still passes (it already references `config/schema.cue`).

## 7. Spec sync at archive time

- [ ] 7.1 Once shipped, archive the change so `openspec/specs/flutter-version-update/spec.md` reflects the as-built behavior (handled by `/opsx:archive`).
