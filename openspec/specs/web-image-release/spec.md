# web-image-release Specification

## Purpose

Define how a pushed tag publishes the `flutter-web` image: which job builds it (`android.Dockerfile --target web`), which registries it fans out to, how it runs in parallel with the Android and Windows releases, and the metadata/label conventions it shares with the Android image. The experience context is the CI engineer who pulls `flutter-web:<version>` at the same tag they already use for `flutter-android`.
## Requirements
### Requirement: Tag push publishes a `flutter-web` image to all release registries

When a tag matching `*` is pushed to the repository, the release job for the web image in `.github/workflows/release.yml` SHALL build `android.Dockerfile` with `--target web` and `--build-arg flutter_version=<tag>`, and SHALL push the resulting image to Docker Hub, GitHub Container Registry, and Quay.io under the repository name `flutter-web` with the tag equal to the Flutter version.

The experience context is the CI engineer who, on the day a new Flutter stable lands, expects to run `docker pull docker.io/<org>/flutter-web:<version>` and find the image at the same tag they already use for `flutter-android`.

#### Scenario: Tag push fans out to all three registries

- **GIVEN** a tag `X.Y.Z` is pushed to the repository
- **WHEN** the web release job completes successfully
- **THEN** `docker.io/<org>/flutter-web:X.Y.Z` exists
- **AND** `ghcr.io/<org>/flutter-web:X.Y.Z` exists
- **AND** `quay.io/<org>/flutter-web:X.Y.Z` exists

#### Scenario: Tag-image consistency

- **WHEN** any of the three published `flutter-web:X.Y.Z` images is pulled and `flutter --version` is invoked inside it
- **THEN** the reported Flutter version is exactly `X.Y.Z`

### Requirement: The published `flutter-web` image builds Flutter web with no runtime downloads

The `flutter-web` image SHALL have the web platform enabled (`flutter config --enable-web`) and the web engine artifacts precached (`flutter precache --web`) at build time, so that the first `flutter build web` inside a pulled image performs no Flutter SDK or engine downloads.

The experience context is the CI engineer whose pipeline pulls `flutter-web:<version>` and runs `flutter build web`: they expect the build to start compiling immediately, not to spend minutes downloading the web SDK on a cold cache — the same "nothing to download at runtime" guarantee the `flutter-android` image gives for Android builds.

#### Scenario: `flutter build web` runs without downloading

- **GIVEN** a freshly pulled `flutter-web:X.Y.Z` image with no network-fetched cache
- **WHEN** `flutter create app && cd app && flutter build web` is run inside the container
- **THEN** the build completes successfully
- **AND** the command output contains no `Downloading` or `Installing` lines from Flutter

#### Scenario: Android tooling is absent from the web image

- **WHEN** the `flutter-web:X.Y.Z` image is inspected
- **THEN** the Android SDK directory (`$ANDROID_HOME`) does not exist
- **AND** no JDK is installed
- **AND** the image is built from the `flutter` base stage, not the `fastlane` or `android` stages

### Requirement: Web release runs in parallel with Android and Windows releases

The web release job SHALL NOT declare a `needs:` dependency on the android or windows release jobs, and those jobs SHALL NOT declare a `needs:` dependency on the web release job. A failure in one SHALL NOT cancel the others.

The experience context is the maintainer cutting a release: they accept that one image may publish while another fails, and prefer fixing the failed one in a follow-up tag rather than blocking all images.

#### Scenario: Android and Windows publish when Web build fails

- **GIVEN** a tag is pushed
- **AND** the web release job fails (e.g., a transient web-precache network error)
- **AND** the android and windows release jobs succeed
- **WHEN** the workflow run completes
- **THEN** the `flutter-android` and `flutter-windows` images are published at all three registries
- **AND** the workflow run is reported as failed (because at least one job failed)
- **AND** the failure surface is the web release job specifically

### Requirement: Web release uses the same metadata conventions as Android release

The web release job SHALL use `docker/metadata-action` with the `images` input set to the same three registry namespaces (`flutter-web` repository name) and the `tags` input set to `type=raw,value=${{ env.FLUTTER_VERSION }}`, mirroring the Android job. The OCI image labels (`org.opencontainers.image.*`) produced by `metadata-action` SHALL be applied to the built image, so that `docker inspect` reports the same OCI label set as the Android image. The Docker Hub repository description for `flutter-web` SHALL be synced from `readme.md` on release, as the Android image is.

The experience context is the operator inspecting `docker inspect <org>/flutter-web:X.Y.Z` and `docker inspect <org>/flutter-android:X.Y.Z` and finding the same set of OCI labels (description, source, revision, version) populated with consistent values.

#### Scenario: OCI labels match the Android image conventions

- **WHEN** `docker inspect <org>/flutter-web:X.Y.Z` is run on a published image
- **THEN** the `org.opencontainers.image.version` label equals `X.Y.Z`
- **AND** the `org.opencontainers.image.source` and `org.opencontainers.image.revision` labels are populated with the same conventions as the `flutter-android` image at the same tag
