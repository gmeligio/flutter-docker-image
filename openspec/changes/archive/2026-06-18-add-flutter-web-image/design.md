## Context

The repo publishes `flutter-android` (from `android.Dockerfile`, `--target android`) and `flutter-windows` (from `windows.Dockerfile`). `android.Dockerfile` is already multi-stage: a neutral `flutter` base (Debian + Flutter SDK, all platforms `--no-enable-*`), then `fastlane` (`FROM flutter`), then `android` (`FROM fastlane`). The android image is the implicit baseline that the `ci-image-*` capabilities describe; windows has its own `windows-image-release` / `windows-image-testing` specs.

Issue #482 asks for a minimal Flutter-web image: Flutter SDK on Linux, no Android SDK/JDK/Fastlane. The base `flutter` stage is already exactly that minus web enablement. Community research (Docker docs, docker-library practice) confirms a single multi-stage Dockerfile is the no-drift default; splitting into a second Dockerfile would require either base duplication (drift) or a published-base-image / templating mechanism — unjustified for one extra same-OS variant.

Constraints: the maintainer is the sole maintainer; CI must not duplicate job logic that then rots; `flutter-android` must remain byte-identical; the in-flight `p13-scout-sbom-provenance` change is rewriting the build/scan path this image will inherit.

## Goals / Non-Goals

**Goals:**
- Publish `flutter-web` to Docker Hub, GHCR, and Quay.io at the Flutter-version tag, with full release + PR-validation parity with `flutter-android`.
- Add the web target with zero impact on the `flutter-android` image and zero base duplication.
- Make the "nothing downloads at runtime" guarantee machine-checked for web (`test/web.yml`).
- Express the second image as CI *parameterization* (matrix), not copied jobs, so a fix to shared steps fixes both.

**Non-Goals:**
- Renaming `android.Dockerfile` (deferred; cosmetic — a single file serving two Linux platforms is acceptable).
- Fixing the Renovate manager-pattern mismatch (tracked in issue #486).
- Publishing a platform-neutral bare `flutter` image, or iOS/Linux-desktop variants (future).
- Dockerfile templating / published-base-image extraction (only needed at >2 Linux variants).

## Decisions

### Decision 1: A `web` stage `FROM flutter`, base stays `--no-enable-web`
Add `FROM flutter AS web` running `flutter config --enable-web && flutter precache --web`. It is a sibling of `fastlane`, not a child of `android`, so it inherits the base (entrypoint, rootless user, git-clone) and pulls in zero Ruby/JDK/Android-SDK.

- **Why base stays neutral:** the `android` stage is `FROM fastlane` ← `FROM flutter`; enabling web in the base would leak `--enable-web` into `flutter-android`. Keeping the base `--no-enable-*` and opting in per-leaf is symmetric with the `android` leaf's `--enable-android` (android.Dockerfile:220) and keeps `flutter-android` byte-identical.
- **Alternative rejected — fold web into the base:** breaks the neutral-base invariant the android image depends on.
- **Alternative rejected — separate `web.Dockerfile`:** Dockerfiles cannot `extend` each other (moby#46673); the only clean split is a published base image (a third artifact + build ordering) or templating — both more surface than one file for one variant.

### Decision 2: Stage `web`, image `flutter-web` (distinct namespaces)
The build target is `web`; the published image repository is `flutter-web`. This mirrors `--target android` → `flutter-android`. The stage name is internal; the image name is the user-facing one and follows the `flutter-<platform>` convention.

- **Why not name the stage `flutter-web`:** stage names are build-internal; matching the convention on the *image* (what users `docker pull`) is what matters. Renaming the stage to match would add nothing and break parallelism with the existing `android` stage name.

### Decision 3: CI parameterization via matrix, not copied jobs
Add `flutter-web` as a matrix dimension over `{IMAGE_REPOSITORY_NAME, target}` in `build.yml` and `release.yml`. `script/setEnvironmentVariables.js` already derives `IMAGE_REPOSITORY_PATH` from `IMAGE_REPOSITORY_NAME` (setEnvironmentVariables.js:51), so the existing build/handoff/cache/test/scan steps work unchanged per matrix leg.

- **Why matrix over copied jobs:** a copied android job set would double the maintenance surface and drift the first time a shared step (handoff, cache ref, scan gate) is fixed in one copy only. The `ci-parallel-image-validation` and `ci-image-handoff` capabilities are written as single definitions; a matrix keeps them single.
- **Trade-off:** matrix legs share the buildcache ref namespace — each image needs its own `…/flutter-web:buildcache` ref to avoid cache collision with android. Handled by parameterizing the cache ref on the image name.

### Decision 4: Sequence after `p13-scout-sbom-provenance`
`p13` is rewriting the build/scan steps (SBOM attestation, Scout `registry://...@<digest>` consumption, attestation push). Landing it first lets the web matrix leg inherit the finalized shape rather than a pre-p13 one that would need re-touching.

## Automated Test Strategy

- **Critical path:** the `flutter-web` image can `flutter build web` with no runtime downloads. This is the load-bearing user guarantee and is verified by a `container-structure-test` command test in `test/web.yml` (`flutter create` → `flutter build web`, `excludedOutput: [Downloading, Installing]`), mirroring `test/android.yml`.
- **Level:** integration-level structure tests against the built image (the project's existing test idiom); no unit tests apply to a Dockerfile.
- **Negative assertions:** absence of Android tooling (`$ANDROID_HOME` does not exist, no JDK) guards against accidentally branching the web stage off `fastlane`/`android`.
- **PR gating:** the web build + test legs run on every `pull_request` (build.yml matrix), turning the PR check red on any failure. New test infrastructure: only `test/web.yml` (a config file; no new runner or harness).
- **Release verification:** tag-image consistency (`flutter --version` == tag) and three-registry presence are covered by the `web-image-release` scenarios.

## Observability

- **Failure surfaces as discrete PR/release checks:** because each image is a matrix leg, a web failure appears as a named `(web)` job on the PR/release run, distinct from the android leg — the maintainer sees *which* image broke, not a merged result. (`web-image-release`: web failure does not cancel android/windows; `web-image-testing`: red web check on assertion failure.)
- **No silent failures:** `container-structure-test` exits non-zero on any failed assertion, failing the job; the no-download regression specifically flips the `excludedOutput` assertion red rather than passing quietly.
- **Build logs are the diagnostic:** the structure-test `excludedOutput` failure prints the offending `Downloading`/`Installing` line, and the build log shows the pull (not a rebuild) per the handoff requirement — making "did it rebuild?" and "did it download?" both directly readable from CI logs.
- **Registry/Scout:** on release, the web image is recorded in Scout (inherited from the shared release path post-p13), so CVE deltas are visible alongside android.

## Risks / Trade-offs

- **Buildcache collision between android and web matrix legs** → parameterize the `cache-from`/`cache-to` ref on the image name (`…/flutter-web:buildcache`), never share one ref across targets.
- **Web stage accidentally branched off `fastlane`/`android`** (bloats the image, defeats the purpose) → the `web-image-release` "Android tooling is absent" scenario and a `test/web.yml` negative assertion catch this.
- **p13 not landed first** → the web leg would inherit the pre-p13 scan/SBOM wiring and need a second touch. Mitigation: explicit ordering dependency (Decision 4); do not start CI wiring until p13 is archived.
- **New Quay.io / Docker Hub `flutter-web` repos must exist with correct push perms** → one-time registry setup; a missing repo surfaces as a release-job push failure on the first tag, isolated to the web leg (does not block android/windows per the parallel-release requirement).
- **`flutter precache --web` adds image size** (web engine artifacts) → accepted; still far smaller than the android image, and required by the no-runtime-download guarantee.

## Migration Plan

1. Land and archive `p13-scout-sbom-provenance`.
2. Add the `web` stage to `android.Dockerfile`; verify `flutter-android` build output is unchanged.
3. Create `flutter-web` repositories on Docker Hub and Quay.io (GHCR auto-creates on first push) with push credentials matching the existing secrets.
4. Parameterize `build.yml` and `release.yml` with the `{IMAGE_REPOSITORY_NAME, target}` matrix; add `test/web.yml`.
5. Update `docs/src` (badges, Running Containers, Roadmap) and regenerate `readme.md`.
- **Rollback:** the web matrix leg / web release job can be removed independently; the android and windows paths are untouched, so reverting the web addition does not affect existing images.

## Open Questions

- None blocking. Filename rename and Renovate fix are explicitly deferred (Non-Goals / issue #486).
