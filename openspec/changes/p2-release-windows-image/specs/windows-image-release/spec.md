## ADDED Requirements

### Requirement: Tag push publishes a `flutter-windows` image to all release registries

When a tag matching `*` is pushed to the repository, the `release_windows` job in `.github/workflows/release.yml` SHALL build `windows.Dockerfile` with `--target flutter` and `--build-arg flutter_version=<tag>`, and SHALL push the resulting image to Docker Hub, GitHub Container Registry, and Quay.io under the repository name `flutter-windows` with the tag equal to the Flutter version.

The experience context is the CI engineer who, on the day a new Flutter stable lands, expects to run `docker pull docker.io/<org>/flutter-windows:<version>` and find the image at the same tag they already use for `flutter-android`.

#### Scenario: Tag push fans out to all three registries

- **GIVEN** a tag `X.Y.Z` is pushed to the repository
- **WHEN** the `release_windows` job completes successfully
- **THEN** `docker.io/<org>/flutter-windows:X.Y.Z` exists
- **AND** `ghcr.io/<org>/flutter-windows:X.Y.Z` exists
- **AND** `quay.io/<org>/flutter-windows:X.Y.Z` exists

#### Scenario: Tag-image consistency

- **WHEN** any of the three published `flutter-windows:X.Y.Z` images is pulled and `flutter --version` is invoked inside it
- **THEN** the reported Flutter version is exactly `X.Y.Z`

### Requirement: Windows release runs in parallel with Android release

The `release_windows` job SHALL NOT declare a `needs:` dependency on `release_android`, and `release_android` SHALL NOT declare a `needs:` dependency on `release_windows`. A failure in one SHALL NOT cancel the other.

The experience context is the maintainer cutting a release: they accept that one architecture may publish while the other fails, and prefer fixing the failed one in a follow-up tag rather than blocking both.

#### Scenario: Android publishes when Windows build fails

- **GIVEN** a tag is pushed
- **AND** the `release_windows` job fails (e.g., transient `windows-2025` runner issue)
- **AND** the `release_android` job succeeds
- **WHEN** the workflow run completes
- **THEN** Android images are published at all three registries
- **AND** the workflow run is reported as failed (because at least one job failed)
- **AND** the failure surface is the `release_windows` job specifically, not `release_android`

### Requirement: Windows release uses the same metadata conventions as Android release

The `release_windows` job SHALL use `docker/metadata-action` with the `images` input set to the same three registry namespaces and the `tags` input set to `type=raw,value=${{ env.FLUTTER_VERSION }}`, mirroring the Android job. The image labels (`org.opencontainers.image.*`) produced by `metadata-action` SHALL be applied to the built image (e.g., as `--label` arguments to `docker build`), so that `docker inspect` reports the same OCI label set as the Android image. `docker/build-push-action` is not a viable mechanism here because it does not support Windows containers (tracked at https://github.com/docker/build-push-action/issues/18).

The experience context is the operator inspecting `docker inspect <org>/flutter-windows:X.Y.Z` and `docker inspect <org>/flutter-android:X.Y.Z` and finding the same set of OCI labels (description, source, revision, version) populated with the same values.

#### Scenario: Labels match Android conventions

- **GIVEN** a successful `release_windows` run for tag `X.Y.Z`
- **WHEN** an operator runs `docker inspect docker.io/<org>/flutter-windows:X.Y.Z` and inspects the `Labels` map
- **THEN** the keys `org.opencontainers.image.source`, `org.opencontainers.image.revision`, `org.opencontainers.image.version`, and `org.opencontainers.image.title` are all present
- **AND** `org.opencontainers.image.version` equals `X.Y.Z`
- **AND** `org.opencontainers.image.revision` equals the commit SHA of the tag

### Requirement: Manual `workflow_dispatch` rebuild is Windows-only

The `release.yml` workflow SHALL continue to declare `workflow_dispatch:`. On `workflow_dispatch`, only the `release_windows` job SHALL execute; `release_android` and its downstream jobs (`update_description`, `record_image`, `set_bootstrap_image`, `create_github_release`) SHALL be skipped via an `if: github.event_name == 'push'` guard on `release_android` (the four downstream jobs auto-skip via their existing `needs: release_android`). The `FLUTTER_VERSION` env var SHALL be set from `github.ref_name`, so that a maintainer can rebuild a single tag's Windows image without re-cutting the Git tag and without re-publishing the Android image, re-pushing the Docker Hub readme, or re-attempting `gh release create` (which would fail because the release already exists).

The experience context is the maintainer recovering from a transient Windows runner failure: they re-run the workflow on the existing tag instead of force-pushing a new one. Android recovery, by contrast, is the established fix-forward + re-tag pattern (see `release.yml` run history) and does not need a `workflow_dispatch` path.

#### Scenario: Manual rebuild produces a fresh Windows image

- **GIVEN** a tag `X.Y.Z` exists in the repository
- **AND** the prior `release_windows` run for that tag failed
- **WHEN** a maintainer triggers `release.yml` via `workflow_dispatch` selecting ref `X.Y.Z`
- **THEN** `release_windows` builds and pushes `flutter-windows:X.Y.Z` to all three registries
- **AND** the existing Windows image digests at those tags are overwritten by the new digests

#### Scenario: Manual rebuild leaves the Android digest untouched

- **GIVEN** a tag `X.Y.Z` exists and was previously published with Android digest `D_a`
- **WHEN** a maintainer triggers `release.yml` via `workflow_dispatch` selecting ref `X.Y.Z`
- **THEN** `release_android` is reported as `skipped`
- **AND** `update_description`, `record_image`, `set_bootstrap_image`, and `create_github_release` are reported as `skipped`
- **AND** the digest at `docker.io/<org>/flutter-android:X.Y.Z` remains `D_a`
- **AND** the run is reported as success (no failed jobs)
