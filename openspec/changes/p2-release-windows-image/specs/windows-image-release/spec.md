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

The `release_windows` job SHALL use `docker/metadata-action` with the `images` input set to the same three registry namespaces and the `tags` input set to `type=raw,value=${{ env.FLUTTER_VERSION }}`, mirroring the Android job. The image labels (`org.opencontainers.image.*`) produced by `metadata-action` SHALL be applied to the built image via `docker/build-push-action`'s `labels` input.

The experience context is the operator inspecting `docker inspect <org>/flutter-windows:X.Y.Z` and `docker inspect <org>/flutter-android:X.Y.Z` and finding the same set of OCI labels (description, source, revision, version) populated with the same values.

#### Scenario: Labels match Android conventions

- **GIVEN** a successful `release_windows` run for tag `X.Y.Z`
- **WHEN** an operator runs `docker inspect docker.io/<org>/flutter-windows:X.Y.Z` and inspects the `Labels` map
- **THEN** the keys `org.opencontainers.image.source`, `org.opencontainers.image.revision`, `org.opencontainers.image.version`, and `org.opencontainers.image.title` are all present
- **AND** `org.opencontainers.image.version` equals `X.Y.Z`
- **AND** `org.opencontainers.image.revision` equals the commit SHA of the tag

### Requirement: Manual `workflow_dispatch` rebuild remains available for Windows

The `release.yml` workflow SHALL continue to declare `workflow_dispatch:`, and the `release_windows` job SHALL be runnable via `workflow_dispatch` with the `FLUTTER_VERSION` env var set from `github.ref_name`, so that a maintainer can rebuild a single tag's Windows image without re-cutting the Git tag.

The experience context is the maintainer recovering from a transient Windows runner failure: they re-run the workflow on the existing tag instead of force-pushing a new one.

#### Scenario: Manual rebuild produces a fresh image

- **GIVEN** a tag `X.Y.Z` exists in the repository
- **AND** the prior `release_windows` run for that tag failed
- **WHEN** a maintainer triggers `release.yml` via `workflow_dispatch` selecting ref `X.Y.Z`
- **THEN** `release_windows` builds and pushes `flutter-windows:X.Y.Z` to all three registries
- **AND** the existing image digests at those tags are overwritten by the new digests
