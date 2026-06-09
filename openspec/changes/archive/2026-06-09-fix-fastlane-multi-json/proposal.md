## Why

The `flutter-android` image cannot run `fastlane`: a bare `fastlane` invocation aborts with `Gem::MissingSpecError: Could not find 'multi_json' (>= 1.14.1)` ([issue #490](https://github.com/gmeligio/flutter-docker-image/issues/490)). The two Fastlane tests in `test/android.yml` fail on cold-cache PR builds, so the image's headline capability — running Flutter Android release tooling — is broken from a fresh build. This is a developer-facing behavior a CI engineer notices the moment they invoke `fastlane` in the container, which clears the relevance gate.

## What Changes

- Replace the bundler project-bundle install of fastlane in `android.Dockerfile` (`bundle init && bundle add --version $fastlane_version fastlane`) with a direct `gem install --no-document --version "$fastlane_version" fastlane multi_json`.
- Install `multi_json` explicitly: it is an **undeclared** runtime dependency of `representable` (in fastlane's Google Play action path), so no fastlane install — bundler or rubygems — pulls it in. This is the actual #490 fix, verified in a cold-built image. Dropping bundler is a paired simplification, not the fix on its own.
- Remove the now-unnecessary scaffolding: the standalone `bundler` gem install, the `FASTLANE_ROOT` directory creation, and the `WORKDIR "$FASTLANE_ROOT"` Gemfile context.
- Keep `GEM_HOME`/`GEM_PATH`/`PATH` and all `FASTLANE_*` opt-out env vars unchanged, so the `fastlane` binstub remains on `PATH` and analytics stay disabled.
- No change to `test/android.yml`; the existing bare-`fastlane` invocations become correct by construction.

## Capabilities

### New Capabilities
- `android-fastlane-runtime`: The `flutter-android` image SHALL provide a `fastlane` executable that runs standalone (without `bundle exec` and from any working directory), with its full transitive gem closure resolvable by RubyGems activation, and with usage analytics opted out.

### Modified Capabilities
<!-- None. No existing spec covers fastlane runtime behavior in the android image. -->

## Impact

- **Code:** `android.Dockerfile` — the `fastlane` stage (lines ~122–135). No other Dockerfile installs or runs fastlane.
- **Images:** `flutter-android` only. `flutter`, `web`, and `windows` images are unaffected.
- **Dependencies:** Drops the explicit `bundler` gem and the per-project `Gemfile`/`Gemfile.lock`; adds an explicit `multi_json` gem (unpinned, like the rest of fastlane's resolved tree). Fastlane's version stays pinned via the `fastlane_version` build arg sourced from `config/version.json`.
- **Tests:** `test/android.yml` "Fastlane can run lanes" and "Fastlane usage is opted-out" — currently failing on cold builds, expected to pass after the change. Verification requires a `--no-cache` build, since buildcache masks the failure.
