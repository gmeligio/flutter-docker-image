## MODIFIED Requirements

### Requirement: Web release uses the same metadata conventions as Android release

The web release job SHALL use `docker/metadata-action` with the `images` input set to the same three registry namespaces (`flutter-web` repository name) and the `tags` input set to `type=raw,value=${{ env.FLUTTER_VERSION }}`, mirroring the Android job. The OCI image labels (`org.opencontainers.image.*`) produced by `metadata-action` SHALL be applied to the built image, so that `docker inspect` reports the same OCI label set as the Android image.

The Docker Hub repository description sync for `flutter-web` is no longer specified here; it is owned by the `dockerhub-repository-description` capability, which syncs the Overview and a per-platform short description for every published image.

The experience context is the operator inspecting `docker inspect <org>/flutter-web:X.Y.Z` and `docker inspect <org>/flutter-android:X.Y.Z` and finding the same set of OCI labels (description, source, revision, version) populated with consistent values.

#### Scenario: OCI labels match the Android image conventions

- **WHEN** `docker inspect <org>/flutter-web:X.Y.Z` is run on a published image
- **THEN** the `org.opencontainers.image.version` label equals `X.Y.Z`
- **AND** the `org.opencontainers.image.source` and `org.opencontainers.image.revision` labels are populated with the same conventions as the `flutter-android` image at the same tag
