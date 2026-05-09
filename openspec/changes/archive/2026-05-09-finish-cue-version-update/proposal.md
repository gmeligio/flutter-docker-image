## Why

The `single_update` branch is mid-migration: it renamed the CUE schema, removed `flutter_version.cue`, and started a CUE-native replacement of `script/updateFlutterVersion.js` — but the migration is incomplete and currently broken. As-is, every scheduled run of `update_version.yml` finishes with no PR: the new CUE step rewrites `config/flutter_version.json` *before* the JS comparator runs, so the JS step always reports "no change" and every downstream job is skipped behind `if: result == 'true'`. On top of that, `cue vet` fails outright because `config/schema.cue` references the renamed-away `#PatchVersion`. CI engineers consuming `ghcr.io/.../flutter-android` therefore stop receiving Flutter updates entirely until this branch is finished.

Relevance gate: this is a spec-worthy change because the CI engineer pulling the image *notices* the absence of new Flutter versions. The pipeline behavior is what they observe, not the wiring underneath.

## What Changes

- Replace `script/updateFlutterVersion.js` with a CUE-native step in `update_version.yml` that fetches `releases_linux.json`, reads the current pinned version, compares, and only writes `config/flutter_version.json` when the upstream stable version actually changed. The step exposes `result` ∈ {`true`,`false`} as a step output so existing downstream `if:` gates keep working unchanged.
- **BREAKING** (internal): delete `script/updateFlutterVersion.js`. Nothing outside the workflow depends on it.
- Source the Android `build-tools` version from Flutter's pinned `engine/src/flutter/tools/android_sdk/packages.txt` for the new Flutter tag, and feed that value into the CUE-driven `version.json` generation. The current orphan `Update Android SDK build tools version` step gets an `id` and its output is consumed.
- Lock the Flutter channel to `"stable"` only in `config/schema.cue` (drop `"beta"`). The fetcher already filters to stable releases via `^\d+\.\d+\.\d+$`, so this just makes the schema match reality.
- Fix `config/schema.cue:20`: replace the dangling `#PatchVersion` reference with `#SemverPatch` so `cue vet` passes.
- Fix `config/android.cue:39`: the length guard checks `input.fileContentTests` but the body indexes `input.commandTests`. Should be `len(input.commandTests) >= 3`.
- Fix `update_version.yml` "Create commit message variable" step: write `commit_message` to `$GITHUB_OUTPUT` (the consumer reads `steps.create_commit_message.outputs.commit_message`); today it writes to `$GITHUB_ENV` and the resulting PR has an empty title and commit message.

## Capabilities

### New Capabilities

- `flutter-version-update`: the scheduled pipeline that detects a new upstream Flutter stable release and opens a PR bumping the image. Covers what the CI engineer sees as a result of the daily scheduled run — whether a PR appears, what it contains, and when no PR is opened.

### Modified Capabilities

_None._ `actions-version-tracking` (the `gx` manifest) is a separate concern and is not touched.

## Impact

- **Workflows**: `.github/workflows/update_version.yml` (rewritten fetch step, fixed commit-message step, build-tools wiring). `.github/workflows/build.yml` already references `config/schema.cue` correctly on this branch.
- **Schema**: `config/schema.cue` (channel narrowed, undefined reference fixed). `config/android.cue` (length-guard typo).
- **Scripts**: `script/updateFlutterVersion.js` deleted. `script/copyFlutterVersion.js` retained — it merges the Flutter sub-document into `version.json` after the Android job runs and has no overlap with the fetch step.
- **Operational**: no secrets, no permissions, no image-runtime change. The first scheduled run after merge produces a PR for whatever Flutter version is current upstream. The next run is a no-op until upstream ships another stable release.
