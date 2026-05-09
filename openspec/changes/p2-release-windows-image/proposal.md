## Why

`release.yml` only builds and publishes the `flutter-android` image on tag. The Windows Dockerfile, the `windows-2025` test workflow, and the `IMAGE_REPOSITORY_NAME: flutter-windows` env var in `windows.yml` all imply a `flutter-windows` image is shipped — but no release path actually pushes it. Once `p1-fix-windows-ci-tests` lands and CI verifies the image, users still cannot `docker pull <org>/flutter-windows:<flutter-version>`. This change adds a `release_windows` job to `release.yml` that mirrors `release_android` for the Windows artifact, so cutting a tag publishes both images.

## What Changes

- Add a new `release_windows` job to `.github/workflows/release.yml` that runs on `windows-2025`, builds `windows.Dockerfile` with `--target flutter`, and pushes the resulting image to Docker Hub, GitHub Container Registry, and Quay.io with the `<flutter-version>` tag (matching the existing Android tagging convention).
- Reuse `script/setEnvironmentVariables.js` and `docker/metadata-action` exactly as `release_android` does, so the tag/label conventions stay identical across architectures.
- Login steps reuse the existing `DOCKER_HUB_*`, `QUAY_*`, and `GHCR` credentials. No new secrets are introduced.
- The new job runs in parallel with `release_android` (no `needs:` dependency between them) so a Windows build failure does not block Android publishing and vice versa.
- The downstream `update_description`, `record_image`, `set_bootstrap_image`, and `create_github_release` jobs that currently `needs: release_android` are NOT changed: they remain Android-scoped because the Docker Hub description, Scout environment, bootstrap-image variable, and changelog all currently reference Android only. Generalizing them is out of scope.
- The `test_windows` PR check from `p1` SHALL be a required check before tags can be cut, but the actual gating is repository-settings-only and not in this PR's diff.

## Capabilities

### New Capabilities

- `windows-image-release`: defines what `release.yml` must do on a tag push so that a `flutter-windows:<flutter-version>` image is published to the same set of registries as the Android image.

### Modified Capabilities

_None._ The existing `flutter-version-update` and `actions-version-tracking` specs are unaffected. `release_android` is unchanged.

## Impact

- Affected files: `.github/workflows/release.yml` (one new job added), `.github/gx.toml` and `.github/gx.lock` (new entries if any new actions are introduced — none expected; the new job uses actions already pinned via the Android job).
- Depends on: `p1-fix-windows-ci-tests` landed (so the image is verified before publishing), but does not depend on `p3-windows-version-schema` (versioning of the Windows artifact follows the existing `flutter.version` convention).
- Operational impact: every tag push triggers an additional `windows-2025` run, which currently takes 30–60 minutes. Tag-push to first-Windows-image-published wall-clock time grows by that amount.
- Cost: `windows-2025` runner minutes are billed; the budget impact should be reviewed before this lands.
- Risk: a flaky Windows build will block release tags. Mitigation is captured in the design (manual workflow_dispatch fallback already exists in `release.yml` and continues to work for Android).
