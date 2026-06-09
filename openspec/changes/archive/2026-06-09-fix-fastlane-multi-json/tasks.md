## 1. Replace bundler install with gem install

- [x] 1.1 In `android.Dockerfile` `fastlane` stage, remove the `bundler` gem install line (`gem install --no-document --version "$BUNDLER_VERSION" bundler`) and the `BUNDLER_VERSION` env declaration
- [x] 1.2 Remove the `FASTLANE_ROOT` env, the `mkdir -p "$FASTLANE_ROOT"`, and the `WORKDIR "$FASTLANE_ROOT"` lines
- [x] 1.3 Replace `RUN bundle init && bundle add --version "$fastlane_version" fastlane` with `RUN gem install --no-document --version "$fastlane_version" fastlane && gem install --no-document multi_json` (keep the `ARG fastlane_version`). NOTE: verification proved `multi_json` must be installed explicitly — `representable` requires it but doesn't declare it, so no fastlane install pulls it in. `gem install fastlane` alone does NOT fix #490.
- [x] 1.4 Confirm `GEM_HOME`, `GEM_PATH`, `PATH` (with `$GEM_HOME/bin`), and the `FASTLANE_OPT_OUT_USAGE` / `FASTLANE_SKIP_UPDATE_CHECK` / `FASTLANE_HIDE_CHANGELOG` env vars are left unchanged

## 2. Cold-build verification

- [x] 2.1 Build the `android` target from scratch with no cache (e.g. `docker build --no-cache --target android ...` via `script/docker_build_android.sh`, or `docker build --target fastlane --no-cache`), confirming the build reaches the fastlane stage cleanly. DONE: cold `--no-cache` build of the `fastlane` target (flutter 3.44.1, fastlane 2.235.0) reached and passed the gem-install step; `multi_json-1.21.1` installed.
- [x] 2.2 In the built image, run `fastlane action debug` and confirm exit 0 with no `Gem::MissingSpecError`. DONE: exit 0, no `MissingSpecError`, 0 "Sending anonymous analytics" lines (opt-out also confirmed).
- [x] 2.3 Run the `test/android.yml` suite against the cold-built image (container-structure-test) and confirm "Fastlane can run lanes" and "Fastlane usage is opted-out" both pass. DONE: reproduced the "can run lanes" setup (Fastfile `hello` lane, bare `fastlane hello` from a sibling dir) → "fastlane.tools finished successfully 🎉", exit 0. Opt-out verified under 2.2. Full container-structure-test (`android` target) deferred to CI — the `fastlane`-target verification exercises the exact bare-binstub path that #490 broke.
- [x] 2.4 If the cold build fails on unrelated Debian apt-pin drift (#486), note it and verify on a cold-build-clean base — that failure is out of scope for this change. DONE: local cold build hit `curl=8.14.1-2+deb13u2` (mirror moved to `deb13u3`); CI on PR #491 failed the same way *before* the fastlane stage, with buildcache no longer masking it. Resolution: bumped `CURL_VERSION` to `deb13u3` in this PR to unblock CI (carries one slice of #486).

## 3. Spec sync and close-out

- [x] 3.1 Confirm the shipped Dockerfile behavior matches `specs/android-fastlane-runtime/spec.md`; adjust the spec if implementation revealed a discrepancy. DONE: spec describes observable behavior (fastlane runs standalone, analytics opted out) — both verified, no spec change needed. Implementation corrected the *root-cause model* (proposal + design updated), not the user-facing contract.
- [x] 3.2 Reference issue #490 in the PR and confirm the previously-failing `Test image (flutter-android)` job is green on a cold-cache build. DONE: PR #491 (references #490). `Test image` PASS (4m41s) — both "Fastlane can run lanes" and "Fastlane usage is opted-out" → `--- PASS`, 0 `MissingSpecError`, 0 failures. `Build and push image` PASS (11m51s, cleared the curl/apt stage), `Scan image` PASS. All 8 checks green.
