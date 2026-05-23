## Why

The scheduled `update_version.yml` run on 2026-05-22 failed because Flutter's `engine/src/flutter/tools/android_sdk/packages.txt` now lists multiple `build-tools;X.Y.Z` entries on a single comma-joined line (e.g. `build-tools;36.1.0,build-tools;35.0.0,...:build-tools`). The current awk one-liner splits only on `;` and `:`, so it extracts `36.1.0,build-tools` instead of `36.1.0`, which then fails `cue vet` one job downstream with a stack trace that points at the schema rather than the extractor. Every upstream Flutter release that ships this packages.txt format will keep breaking the upgrade pipeline until the extractor is fixed *and* validation runs at the producer.

## What Changes

- Fix the build-tools extractor in `.github/workflows/update_version.yml` to handle packages.txt lines that contain multiple comma-joined `build-tools;X.Y.Z` entries, selecting the highest version (the first entry, by Flutter's convention).
- Anchor the `grep` to start-of-line (`^build-tools`) so unrelated future categories cannot match.
- Add a `cue vet config/schema.cue -d '#Version' config/version.json` step at the end of `update_android_version`, mirroring the validation already present in `update_windows_version`, so producer jobs fail fast on bad output instead of leaking malformed data to a downstream validator.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `flutter-version-update`: Strengthen the "Build-tools version tracks the new Flutter tag" requirement to explicitly cover the multi-version packages.txt format, and add a requirement that each producer job in `update_version.yml` validates its own artifact with `cue vet` before upload.

## Impact

- `.github/workflows/update_version.yml` — extractor at line 244 and new vet step in `update_android_version`.
- `openspec/specs/flutter-version-update/spec.md` — clarified scenario and a new producer-side validation requirement.
- No code under `script/` or `config/` changes; schema and gradle script are correct as-is.
- No breaking changes for image consumers — this only unblocks the scheduled upgrade workflow.
