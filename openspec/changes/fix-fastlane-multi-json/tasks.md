## 1. Replace bundler install with gem install

- [x] 1.1 In `android.Dockerfile` `fastlane` stage, remove the `bundler` gem install line (`gem install --no-document --version "$BUNDLER_VERSION" bundler`) and the `BUNDLER_VERSION` env declaration
- [x] 1.2 Remove the `FASTLANE_ROOT` env, the `mkdir -p "$FASTLANE_ROOT"`, and the `WORKDIR "$FASTLANE_ROOT"` lines
- [x] 1.3 Replace `RUN bundle init && bundle add --version "$fastlane_version" fastlane` with `RUN gem install --no-document --version "$fastlane_version" fastlane` (keep the `ARG fastlane_version`)
- [x] 1.4 Confirm `GEM_HOME`, `GEM_PATH`, `PATH` (with `$GEM_HOME/bin`), and the `FASTLANE_OPT_OUT_USAGE` / `FASTLANE_SKIP_UPDATE_CHECK` / `FASTLANE_HIDE_CHANGELOG` env vars are left unchanged

## 2. Cold-build verification

- [ ] 2.1 Build the `android` target from scratch with no cache (e.g. `docker build --no-cache --target android ...` via `script/docker_build_android.sh`, or `docker build --target fastlane --no-cache`), confirming the build reaches the fastlane stage cleanly
- [ ] 2.2 In the built image, run `fastlane action debug` and confirm exit 0 with no `Gem::MissingSpecError`
- [ ] 2.3 Run the `test/android.yml` suite against the cold-built image (container-structure-test) and confirm "Fastlane can run lanes" and "Fastlane usage is opted-out" both pass
- [ ] 2.4 If the cold build fails on unrelated Debian apt-pin drift (#486), note it and verify on a cold-build-clean base — that failure is out of scope for this change

## 3. Spec sync and close-out

- [ ] 3.1 Confirm the shipped Dockerfile behavior matches `specs/android-fastlane-runtime/spec.md`; adjust the spec if implementation revealed a discrepancy
- [ ] 3.2 Reference issue #490 in the PR and confirm the previously-failing `Test image (flutter-android)` job is green on a cold-cache build
