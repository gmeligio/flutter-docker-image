## Why

`config/flutter_version.json` duplicates the `flutter` block that already lives in `config/version.json`. `version.json` is the manifest every consumer actually reads (`script/setEnvironmentVariables.js`, `build.yml` build-args, `windows.yml`, `release.yml`), and `config/schema.cue`'s `#Version` embeds `#FlutterVersion`, so `version.json` is already schema-complete for Flutter. `flutter_version.json` only ever served two *internal* roles: the change-detection anchor for the Flutter producer, and (after `p12-symmetric-platform-updates`) the "Flutter fragment" overlaid in `compose-version-manifest`.

`p12` made compose fold `flutter_version.json` into `version.json` and then `rm` it from the generated PR — but left `build.yml`'s `validate-version-files` and the Flutter producer's trigger still requiring the file. The result: the Build check fails on every auto-generated bump PR (PR #496: `stat config/flutter_version.json: no such file or directory`), and the next scheduled run would read a change-detection anchor the prior PR deleted — a latent self-destruct.

The deeper observation, found while scoping the fix: the duplicate file is one symptom of a larger maintenance cost — the **fragment-artifact machinery** `p12` introduced. Every platform producer stages a fragment file, uploads it as an artifact, and exposes an artifact-id; `compose-version-manifest` builds a dynamic id-list, downloads with `merge-multiple`, and overlays each file (with historical `rm`-before-download "can't overwrite" workarounds). None of that data is load-bearing as *files*: every new value per cycle is a handful of small scalars, and `test/android.yml` is fully *derived* from `config/version.json` by `script/update_test.sh` (`cue export config/android.cue`), so it never needs to travel between jobs at all.

This change makes `config/version.json` the single committed source of truth and removes the artifact machinery: each platform producer reports its block as a small JSON **job output**; a single job assembles those onto `version.json`, regenerates `test/android.yml` from it, validates once, and opens the PR. `config/flutter_version.json` is deleted.

## What Changes

- **Remove `config/flutter_version.json`** (the committed duplicate) and **`script/copyFlutterVersion.js`** (already dead — no workflow references it).
- **MODIFIED (workflow) — producers report blocks as job outputs, not artifacts.** Each producer overlays its block onto its in-job `config/version.json`, validates with `cue vet -d '#Version'` (unchanged producer self-check), then emits `jq -c '{<block>}'` as a job **output** instead of uploading a fragment:
  - `update-flutter-version` reads the current pinned version from `config/version.json` (`.flutter.version`), resolves upstream stable, and outputs `flutter_channel` / `flutter_commit` / `flutter_version` + a `changed` gate. No file write survives the job; no artifact.
  - `update-android-version` outputs `android_block` (`{android, fastlane}`); it no longer generates or uploads `test/android.yml`, and no longer downloads/`rm`s `flutter_version.json`. It reads `FLUTTER_VERSION` / `FLUTTER_CHANNEL` from the Flutter producer's outputs.
  - `update-windows-version` outputs `windows_block` (`{windows}`); it drops the `flutter_version.json` download/`rm` it never used.
- **BREAKING (workflow) — collapse compose + validate + PR into one job.** `compose-version-manifest` and `validate-config-version` are removed; the final job (`compose-and-open-pr`) checks out the base manifest, overlays the platform blocks from job outputs via `jq --arg`/`--argjson` (Flutter unconditional; Android/Windows guarded on a non-empty block output, else the base block carries forward), regenerates `test/android.yml` via `script/update_test.sh`, validates the composed manifest with `cue vet -d '#Version' config/version.json` as a gating step, then opens the PR. No version artifacts are produced or consumed.
- **MODIFIED (workflow) — `build.yml` `validate-version-files`:** validate only `config/version.json` with `cue vet -d '#Version'` (which covers the `flutter` block and its stable-channel constraint). Remove the `flutter_version.json` line.

## Capabilities

### New Capabilities

(none — this change consolidates the source of truth and simplifies the assembly mechanism for an existing capability)

### Modified Capabilities

- `flutter-version-update`: four requirements are restated:
  - **Trigger anchor** reads `config/version.json` (`.flutter.version`), not `config/flutter_version.json`.
  - **Producer self-validation** is preserved but producers now **emit a block job output** instead of uploading a fragment artifact; the Flutter producer is fully symmetric (validates `#Version`, no standalone `#FlutterVersion` artifact).
  - **Coherent, validated `version.json`** is assembled and validated in a single `compose-and-open-pr` job (the `compose-version-manifest` and `validate-config-version` jobs are removed); `test/android.yml` is **regenerated** from the composed manifest rather than shipped as an artifact; a skipped platform (empty block output) carries its base block forward.
  - **Stable-channel enforcement** is via `cue vet -d '#Version' config/version.json`.

## Impact

- Affected files: `.github/workflows/update-version.yml` (producers emit outputs; compose/validate/PR collapse into one job; all version artifacts removed), `.github/workflows/build.yml` (`validate-version-files` validates `version.json` only), `config/flutter_version.json` (deleted), `script/copyFlutterVersion.js` (deleted, dead).
- No change to `config/schema.cue` (`#FlutterVersion` stays embedded in `#Version`), `config/version.json`'s committed role or data contract, `script/update_test.sh` / `config/android.cue` (now *called* downstream rather than in the Android job), `script/setEnvironmentVariables.js`, or any image-build workflow. The upgrade PR's `config/version.json` and `test/android.yml` are byte-equivalent to today's happy-path output.
- The Windows `vs-manifests` forensic artifact (independent debug upload) is unaffected. No external consumer reads the removed version fragments (verified by grep — only the now-removed internal jobs did).
- `update-version.yml` runs on `schedule`/`workflow_dispatch`, not on PRs to `main`, so its job names are not branch-protection required checks; merging/renaming its jobs does not affect required-check configuration.
- A pre-existing branch (`claude/action-failure-root-cause-oh5n25`) implements an interim design (Flutter via job outputs, Android/Windows still fragments). This change supersedes it: all platforms use outputs and the back-half jobs collapse.
- Relevance gate: this change passes — it modifies spec-level behavior of `flutter-version-update` (the trigger anchor, the producer model, and the composition/validation topology), all observable to the CI engineer who watches for upgrade PRs and triages failed scheduled runs, and it removes a defect that reddens every auto-generated bump PR's Build check.
