## 1. Version manifest + schema

- [ ] 1.1 Add `android.java: { "version": <current major> }` (e.g. `17`) to `config/version.json`, placed alongside the other `android` sub-fields
- [ ] 1.2 Add `java!: #PlatformVersion` to the `android` struct of `#Version` in `config/schema.cue` (bare integer major, modeled like `platforms`)
- [ ] 1.3 Run `cue vet config/schema.cue -d '#Version' config/version.json` and confirm it exits 0

## 2. Producer derivation (update-version.yml)

- [ ] 2.1 In `update-android-version`, after the "Update default Android platform versions" step, add a step that runs `script/java_version.sh` inside the `flutter-android` container to read the installed JDK major
- [ ] 2.2 Write the derived major into `android.java.version` via `jq` as an **integer** (not a string), before the existing "Validate version.json with CUE" step
- [ ] 2.3 Confirm the producer's `cue vet` self-validation now covers `android.java`; a missing or non-integer value fails the job (so `android_block` is not emitted)
- [ ] 2.4 Confirm the emitted `android_block` (`jq -c '{android, fastlane}'`) includes `android.java`
- [ ] 2.5 Confirm the Android-skip path carries forward the base-branch `android.java` unchanged (no derivation; existing `compose-and-open-pr` carry-forward handles it)

## 3. README content (docs/src)

- [ ] 3.1 In `docs/src/content.mdx`, add a `javaVersion` export reading `versionJson.android.java.version`
- [ ] 3.2 Replace the single "Predownloaded SDKs and tools in Android" block with two per-image headline lists
- [ ] 3.3 `flutter-android` list: Flutter SDK `{flutterVersion}`, Java (OpenJDK) `{javaVersion}`, Android SDK Platform `{androidPlatformVersions}`, Android NDK `{androidNdkVersion}`, Gradle `{gradleVersion}`, Fastlane `{fastlaneVersion}`
- [ ] 3.4 `flutter-web` list: Flutter SDK `{flutterVersion}`; a line "Web engine — precached (no runtime download)" with **no** version number
- [ ] 3.5 Do not list the Dart SDK version or Android SDK Build Tools / CMake / Command-line Tools in the headline lists
- [ ] 3.6 Regenerate committed docs with `mise run docs`; verify the `readme.md` diff shows the two lists and the Java version

## 4. Verify

- [ ] 4.1 `cue vet config/schema.cue -d '#Version' config/version.json` is green and `readme.md` is in sync with `content.mdx` (the `update-docs` check would pass)
- [ ] 4.2 Confirm `build.yml` version-file / schema validation stays green with the new required field
- [ ] 4.3 (Deferred) optional `test/android.yml` assertion that `java -version`'s major equals `android.java.version` — deferred; requires extending `config/android.cue` test-templating to inject the Java field
