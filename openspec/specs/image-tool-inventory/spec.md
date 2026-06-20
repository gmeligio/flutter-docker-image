# image-tool-inventory Specification

## Purpose

The README presents, per published image, a list of that image's most important ("main") tools and the exact versions it ships, so a CI engineer can compare `flutter-android` and `flutter-web` and pin one without pulling it. The versions are sourced from `config/version.json` (through `docs/src/content.mdx`) so the README cannot drift from the published image, and the list is deliberately curated — it excludes tools that are not decision-relevant for image selection.

## Requirements

### Requirement: README lists main tools and versions per published image

The README SHALL present, for each published Linux image, a list of that image's **main** tools together with the exact version the image ships, so a CI engineer can see what each image contains without pulling it. The `flutter-android` list SHALL include the Flutter SDK, Java (OpenJDK), the Android SDK Platform, the Android NDK, Gradle, and Fastlane. The `flutter-web` list SHALL include the Flutter SDK and a statement that the web engine is precached with no runtime download. Every version SHALL be sourced from `config/version.json` (through `docs/src/content.mdx` exports) rather than hand-written, so the README cannot drift from the published image.

The Dart SDK version SHALL NOT appear in the main tool lists (Dart ships bundled with Flutter and is not separately tracked), and the Android SDK Build Tools version SHALL NOT appear in the main tool lists (it is not a main tool for image selection).

The experience context is a CI engineer on the README, comparing `flutter-android` and `flutter-web` before pinning one in their pipeline.

#### Scenario: Android image main tool list is rendered

- **GIVEN** `config/version.json` pins `flutter`, `android.java`, `android.platforms`, `android.ndk`, `android.gradle`, and `fastlane`
- **WHEN** `readme.md` is generated from `docs/src`
- **THEN** the `flutter-android` section lists the Flutter SDK, Java (OpenJDK), Android SDK Platform, Android NDK, Gradle, and Fastlane
- **AND** each entry shows the corresponding version from `config/version.json`

#### Scenario: Web image main tool list is rendered

- **GIVEN** the `flutter-web` image ships the Flutter SDK with the web engine precached
- **WHEN** `readme.md` is generated from `docs/src`
- **THEN** the `flutter-web` section lists the Flutter SDK with its version
- **AND** it states the web engine is precached with no runtime download
- **AND** it does not show a separate web-engine version number

#### Scenario: Java version is sourced from the manifest

- **GIVEN** `android.java.version` is `N` in `config/version.json`
- **WHEN** `readme.md` is generated from `docs/src`
- **THEN** the `flutter-android` section shows Java (OpenJDK) `N`
- **AND** `docs/src/content.mdx` reads the value from `versionJson.android.java.version` rather than hard-coding it

#### Scenario: Dart and Build Tools are intentionally excluded

- **GIVEN** the main tool lists are generated
- **WHEN** a CI engineer reads the `flutter-android` list
- **THEN** no Dart SDK version is shown
- **AND** the Android SDK Build Tools version is not listed
