# android-fastlane-runtime Specification

## Purpose

Defines how the `flutter-android` image provides `fastlane` so a CI engineer can run Flutter Android release tooling. Covers the invariant that a bare `fastlane` invocation resolves its full gem closure standalone (no `bundle exec`, any working directory), and that usage analytics are opted out. The desktop user this serves is the CI engineer invoking `fastlane <lane>` inside the container.

## Requirements

### Requirement: Fastlane runs standalone in the flutter-android image

The `flutter-android` image SHALL provide a `fastlane` executable on `PATH` whose full transitive gem closure is resolvable by RubyGems' own activation, so that a bare `fastlane` invocation runs lanes from any working directory without `bundle exec`.

**Experience context:** A CI engineer running Flutter Android release tooling invokes `fastlane <lane>` directly inside the container (the documented usage; `test/android.yml`'s "Fastlane can run lanes" exercises exactly this). Before this requirement, fastlane was installed into a project bundle via `bundle add` and the undeclared `representable` dependency `multi_json` was never installed, so a bare invocation failed with `Gem::MissingSpecError: Could not find 'multi_json'` on cold-cache builds — the image's headline Android capability was broken from a fresh build (issue #490). The fix installs fastlane via `gem install` and installs `multi_json` explicitly, so the bare-binstub closure is complete.

#### Scenario: Bare fastlane invocation runs a lane from an unrelated directory

- **GIVEN** the `flutter-android` image built from a cold (`--no-cache`) build
- **AND** a Flutter project at `test_app/android` with a `Fastfile` defining a `hello` lane
- **WHEN** a CI engineer runs `fastlane hello` from `test_app/android` (no `bundle exec`)
- **THEN** fastlane resolves its full gem closure, runs the lane, and exits 0
- **AND** no `Gem::MissingSpecError` (e.g. for `multi_json`) is raised

#### Scenario: Fastlane action loads its full default action set

- **GIVEN** the `flutter-android` image
- **WHEN** `fastlane` loads its default actions (including Google Play actions that pull in `representable` → `multi_json`)
- **THEN** every transitively required gem is activatable
- **AND** the command does not abort during action loading

### Requirement: Fastlane usage analytics are opted out

The `flutter-android` image SHALL ship fastlane with usage analytics disabled, so that invoking `fastlane` does not send anonymous analytics information.

**Experience context:** A CI engineer running fastlane in an unattended pipeline must not have the container phone home. The image sets `FASTLANE_OPT_OUT_USAGE=YES` (alongside `FASTLANE_SKIP_UPDATE_CHECK` and `FASTLANE_HIDE_CHANGELOG`); `test/android.yml`'s "Fastlane usage is opted-out" asserts on this.

#### Scenario: Fastlane does not report analytics

- **GIVEN** the `flutter-android` image
- **WHEN** a CI engineer runs `fastlane action debug`
- **THEN** the output does not contain "Sending anonymous analytics information"
