## 1. Prerequisite

- [ ] 1.1 Confirm `p13-scout-sbom-provenance` is landed and archived (the web matrix leg inherits its build/scan/SBOM wiring)

## 2. Dockerfile

- [ ] 2.1 Add `FROM flutter AS web` stage to `android.Dockerfile`, branching off the base (sibling of `fastlane`)
- [ ] 2.2 In the `web` stage, run `flutter config --enable-web && flutter precache --web`; leave the base `flutter` stage's `--no-enable-web` unchanged
- [ ] 2.3 Build `--target android` locally and confirm the `flutter-android` image is unchanged (no new layers, same digest aside from base bumps)
- [ ] 2.4 Build `--target web` locally and confirm: image runs `flutter build web` with no `Downloading`/`Installing`, `$ANDROID_HOME` is absent, no JDK present
- [ ] 2.5 Add/confirm a `web` service target in `docker-compose.yml` mapping to `--target web`

## 3. Tests

- [ ] 3.1 Create `test/web.yml` mirroring `test/android.yml`: a `flutter create` + `flutter build web` command test with `excludedOutput: [Downloading, Installing]`
- [ ] 3.2 Add a structure-test assertion that the Android SDK directory (`$ANDROID_HOME`) does not exist and no JDK is installed
- [ ] 3.3 Run `container-structure-test --config test/web.yml` against the locally built web image and confirm green

## 4. PR validation CI (build.yml)

- [ ] 4.1 Parameterize the build/test/scan jobs over a `{IMAGE_REPOSITORY_NAME, target}` matrix including `flutter-web`/`web` and `flutter-android`/`android`
- [ ] 4.2 Parameterize the buildcache ref on image name so web uses `…/flutter-web:buildcache` (no collision with android)
- [ ] 4.3 Point the test job at `test/web.yml` for the web leg (per-target config selection)
- [ ] 4.4 Confirm the web leg consumes the image via handoff (pull / artifact load), never `docker build` in test/scan
- [ ] 4.5 Confirm the fork-PR gate still skips the web Scout scan leg while the web build+test legs run on the local artifact
- [ ] 4.6 Open a draft PR touching `android.Dockerfile` and verify named `(web)` and `(android)` checks both appear and pass

## 5. Release CI (release.yml)

- [ ] 5.1 Add/parameterize a web release job: build `android.Dockerfile --target web`, push to Docker Hub + GHCR + Quay.io under `flutter-web:<version>`
- [ ] 5.2 Use `docker/metadata-action` with the three `flutter-web` registry namespaces and `type=raw,value=${{ env.FLUTTER_VERSION }}`; apply OCI labels matching the android conventions
- [ ] 5.3 Ensure the web release job has no `needs:` on android/windows release and vice versa (parallel, independent failure)
- [ ] 5.4 Add Docker Hub description sync for the `flutter-web` repository (peter-evans/dockerhub-description), reading `readme.md`
- [ ] 5.5 Ensure the web image is recorded in Scout on release via the shared (post-p13) release path

## 6. Registries

- [ ] 6.1 Create the `flutter-web` repository on Docker Hub with push credentials matching existing secrets
- [ ] 6.2 Create the `flutter-web` repository on Quay.io with robot-token push access (GHCR auto-creates on first push)

## 7. Docs

- [ ] 7.1 Add `flutter-web` badges and a Running Containers table row in `docs/src` sources
- [ ] 7.2 Tick **Web** off the Roadmap in `docs/src`
- [ ] 7.3 Regenerate `readme.md` from `docs/src` and verify the diff

## 8. Verify

- [ ] 8.1 Validate the change: `openspec validate add-flutter-web-image`
- [ ] 8.2 Cut a test tag (or dry-run) and confirm `flutter-web:<version>` exists on all three registries with `flutter --version` == tag
- [ ] 8.3 Confirm a forced no-precache build turns the `test/web.yml` no-download assertion red (negative test)
