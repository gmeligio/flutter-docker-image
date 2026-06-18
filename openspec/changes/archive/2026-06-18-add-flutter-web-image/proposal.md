## Why

CI engineers building Flutter **web** apps in Docker only need the Flutter SDK on a Linux base — not the Android SDK, JDK, or Fastlane that the `flutter-android` image carries. Pulling `flutter-android` to run `flutter build web` wastes bandwidth and cache on a large, irrelevant download. The previously-popular minimal image (`cirruslabs/docker-images-flutter`) is discontinued ([issue #482](https://github.com/gmeligio/flutter-docker-image/issues/482)), leaving these users without a maintained option.

This needs a spec because it introduces new user-observable behavior — a new published image and a new PR check — at the same altitude as the existing `windows-image-release` / `windows-image-testing` specs. It is not an implementation detail of an existing capability.

## What Changes

- Add a `web` stage to `android.Dockerfile`, branching `FROM flutter` (sibling of `fastlane`). It runs `flutter config --enable-web` and `flutter precache --web` so the image can `flutter build web` with no runtime downloads. The base `flutter` stage stays `--no-enable-web`; the `web` leaf opts in, symmetric with how the `android` leaf does `--enable-android`. `flutter-android` is unaffected.
- Publish a new image **`flutter-web`** to Docker Hub, GHCR, and Quay.io at the Flutter-version tag, mirroring the `flutter-android` / `flutter-windows` naming and release fan-out.
- Build the `flutter-web` image on every PR (build + container-structure-test), at full parity with the android PR path (`build.yml`): same handoff/cache/scan wiring, added as a matrix row keyed on `{IMAGE_REPOSITORY_NAME, target}` rather than a copied job.
- Add `test/web.yml` (container-structure-test) asserting `flutter build web` succeeds with no `Downloading`/`Installing` output, mirroring `test/android.yml`.
- Update docs: add `flutter-web` badges + Running Containers row, and tick **Web** off the readme Roadmap.

Note: the build **stage** is named `web`; the published **image** is `flutter-web`. These live in different namespaces (`--target web` → tag `…/flutter-web:<version>`), intentionally mirroring `--target android` → `flutter-android`.

## Capabilities

### New Capabilities

- `web-image-release`: Tag-push publishing of the `flutter-web` image to all three release registries at the Flutter-version tag, in parallel with the android and windows releases, using the same metadata/label conventions.
- `web-image-testing`: Pull-request validation of the `flutter-web` image — build, container-structure-test (including a no-runtime-download `flutter build web`), and the shared handoff/cache/scan path at parity with android.

### Modified Capabilities

<!-- None. The web image reuses ci-image-build-cache, ci-image-handoff,
     ci-image-tag-lifecycle, ci-parallel-image-validation, and
     ci-runtime-tool-versioning as-is via matrix parameterization;
     no existing requirement changes. -->

## Impact

- **Dockerfile**: `android.Dockerfile` gains a `web` stage (`FROM flutter`). The `flutter`, `fastlane`, and `android` stages are unchanged and `flutter-android` stays byte-identical.
- **CI**: `.github/workflows/build.yml` and `.github/workflows/release.yml` gain `flutter-web` as a matrix dimension over `{IMAGE_REPOSITORY_NAME, target}`. Plumbing already keys off `IMAGE_REPOSITORY_NAME` via `script/setEnvironmentVariables.js`, so no script change is required.
- **Tests**: new `test/web.yml`.
- **Docs**: `docs/src` sources for badges, Running Containers table, and Roadmap; regenerated `readme.md`.
- **Registries**: a new `flutter-web` repository on Docker Hub, GHCR, and Quay.io (Docker Hub description sync added).
- **Sequencing**: depends on `p13-scout-sbom-provenance` landing first, so `flutter-web` inherits the finalized SBOM/Scout/attestation wiring rather than the pre-p13 shape.
- **Not in scope**: renaming `android.Dockerfile` (a single file serves both Linux platforms; deferred as cosmetic). The Renovate manager-pattern fix is tracked separately ([issue #486](https://github.com/gmeligio/flutter-docker-image/issues/486)).
