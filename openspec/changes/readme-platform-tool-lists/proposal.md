## Why

The README's Features section carries a single "Predownloaded SDKs and tools in Android" bullet block that is both incomplete and asymmetric: it names the NDK and Gradle but omits other pinned tools, names **no** tools for the `flutter-web` image at all, and folds everything into one Android-only list. A CI engineer choosing between `flutter-android` and `flutter-web` cannot see, **per image**, the headline tools and the exact versions they would get — the single most decision-relevant fact when pinning a CI image.

The Java version compounds this. JDK/AGP compatibility is one of the versions a CI engineer routinely needs, yet Java is pinned only inside `android.Dockerfile` (the `openjdk-17-jdk-headless` package name and the `java-17-openjdk-amd64` `JAVA_HOME` path) and tracked nowhere in `config/version.json`. The README cannot show it without hard-coding a second, drift-prone copy of "17".

This needs a spec because it changes user-observable behavior — what the README tells a CI engineer about each published image — and modifies the `flutter-version-update` capability (the `update-android-version` producer and `config/schema.cue`) to make the Java version a tracked, validated field derived from the image itself. It is not a pure implementation detail.

## What Changes

- **README** (`docs/src/content.mdx`): replace the single Android-only "Predownloaded SDKs and tools" block with two **per-image headline tool lists**:
  - `flutter-android`: Flutter SDK, Java (OpenJDK), Android SDK Platform, Android NDK, Gradle, Fastlane — each with its version.
  - `flutter-web`: Flutter SDK, plus a qualitative "Web engine — precached (no runtime download)" line.
  - Intentionally **excluded**: the **Dart SDK version** (bundled with Flutter; not separately tracked) and **Android SDK Build Tools** (not a headline tool for image selection). CMake and Command-line Tools likewise stay out of the headline list.
- **`config/version.json` + `config/schema.cue`**: add `android.java.version` as a positive-integer major (e.g. `17`); `#Version`'s `android` struct requires it.
- **`update-version.yml`**: the `update-android-version` producer derives the Java major from the running `flutter-android` container via the existing `script/java_version.sh` and writes it into `android.java.version`, so the emitted `android_block` carries it. No second source of truth is hand-maintained — the value mirrors the JDK actually installed in the image.
- **`content.mdx`**: source the displayed Java version from `android.java.version`; show the web engine as a precache **guarantee**, not a fabricated version number (in the post-3.27 monorepo the web engine has no human-meaningful version distinct from the Flutter SDK).

## Capabilities

### New Capabilities

- `image-tool-inventory`: The README presents, per published image, a headline list of the most important tools and their versions, sourced from `config/version.json`, so a CI engineer can see at a glance what each image ships.

### Modified Capabilities

- `flutter-version-update`: The `update-android-version` producer additionally derives the installed Java major version into `android.java.version`, and `config/schema.cue` requires that field — so the version the README shows is the version the image ships.

## Impact

- **Docs**: `docs/src/content.mdx` (two per-image lists, `javaVersion` export, web precache line); regenerated `readme.md`.
- **Config**: `config/version.json` gains `android.java`; `config/schema.cue` `#Version.android` gains `java!`.
- **CI**: `.github/workflows/update-version.yml` `update-android-version` job gains a Java-derivation step (reusing `script/java_version.sh`); the emitted `android_block` now includes `android.java`. Carry-forward on the Android-skip path is unchanged (the base `android.java` rides along with the rest of the `android` block).
- **Tests**: no change required — `test/android.yml` is regenerated from the manifest but does not assert Java today (an optional structure-test assertion is deferred).
- **Not in scope**: tracking the Dart SDK version; showing Build Tools / CMake / Command-line Tools in the headline list; parameterizing the Dockerfile's JDK major from `version.json` (the install remains the source of truth; `version.json` mirrors it).
