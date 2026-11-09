# Proposal

## Why

`ci-parallel-image-validation` no longer matches `.github/workflows/build.yml` (#597): no `## Purpose`, pre-#477 job keys, a single-image model, and a finished one-time migration. Only one of its four requirements is unique; the rest duplicate `ci-image-handoff` and `ci-image-vulnerability-scan`. `ci-image-handoff` and `ci-image-build-cache` drifted the same way (stale output names, `test_image`, `flutter-android` only). See `research.md`.

Relevance gate: the maintainer reads these specs to know what the PR checks page shows (`Build and push image (<name>)`, `Test image (<name>)`, `Scan image (<name>)`) and which checks a fork contributor sees. Wrong specs mislead that reading.

## What Changes

- **BREAKING (specs only)**: remove capability `ci-parallel-image-validation`. Its unique rule moves to `ci-image-handoff`; its fork-gate rule moves to `ci-image-vulnerability-scan`; its rebuild ban moves to `ci-image-handoff`; its migration requirement is dropped.
- `ci-image-handoff`: describe the real handoff (`tag`, `is_fork`, `flutter_version` outputs; per-image artifact `image-<run_id>-<name>`); add "consumers never rebuild" and "test and scan validate each image in parallel after build", named by check display name.
- `ci-image-vulnerability-scan`: add the job-level fork gate as its own requirement.
- `ci-image-build-cache`: per-image `ghcr.io/<owner>/<image>:buildcache`; build job is `build-image`.
- `ci-image-handoff` Purpose and the `build.yml:189` comment stop naming the removed spec / `test_image`.
- No workflow behavior changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ci-image-handoff`: handoff outputs and artifact name match `build.yml`; adds no-rebuild and parallel per-image validation requirements.
- `ci-image-vulnerability-scan`: adds the job-level fork-PR gate on `scan-image`.
- `ci-image-build-cache`: cache tag is per image; scenarios reference `build-image`.
- `ci-parallel-image-validation`: deleted outright (no delta; see design.md D1).

## Impact

- `openspec/specs/{ci-image-handoff,ci-image-vulnerability-scan,ci-image-build-cache}/spec.md` changed; `openspec/specs/ci-parallel-image-validation/` deleted.
- `.github/workflows/build.yml:189` comment only.
- Closes #597. Leaves #561 (other missing Purposes), #598 (CI spec validation), #599 (config audience) open.
