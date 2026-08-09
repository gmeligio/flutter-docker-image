Ordered by the migration plan in `design.md`: each group is independently
revertable, and group 3 is the only one that can change the published image
(5.1 edits `android.Dockerfile` but only its comments).

`manifest-build-arg-wiring` is a **separate change**. This one declares
`ARG android_java_version` and passes it however the build currently passes
arguments — one export plus four build-arg lines, the five edits this repo charges
per manifest field. If the wiring change has landed first, that collapses to one
table row. Neither change blocks the other.

## 1. Derive Java from Flutter's floor (design D1, D2)

- [x] 1.1 In `script/updateAndroidVersions.gradle.kts`, resolve `com.flutter.gradle.DependencyVersionChecker` via `Class.forName` and get its `INSTANCE` field (Kotlin `object` singleton)
- [x] 1.2 Find the zero-arg getter whose name is `getErrorJavaVersion` or starts with `getErrorJavaVersion$` (prefix match — do NOT hardcode the `$gradle` module suffix); `error(...)` with the sorted member list if absent
- [x] 1.3 Invoke it, cast to `org.gradle.api.JavaVersion`, and take `.majorVersion.toInt()` — not `toString()`, which returns `"1.8"` for Java 8
- [x] 1.4 Add `"java" to mapOf("version" to javaMajor)` to the task's `newJsonMap`, alongside the existing `platforms`/`gradle`/`buildTools`/`ndk` entries
- [x] 1.5 Print the derived value, its provenance, and the resolved getter name (`Derived Java major from errorJavaVersion (getErrorJavaVersion$gradle): 17`)
- [x] 1.6 Confirm the derivation resolves against the **currently pinned** Flutter (`flutter.version` in `config/version.json`, `3.44.9` at time of writing) — not only against the commit the design cites — and yields `17`, producing **no diff** in `config/version.json`. Run this with the old `java_version.sh` step still in place: both sources then write `android.java.version` on the same run, so agreement shows up as an empty diff and disagreement as a visible one. The empty diff is the validation
- [x] 1.7 If the pinned Flutter's floor is not 17, stop and reassess before continuing. The "no diff" premise collapses: the change becomes a manifest-value change with image consequences, group 3 would ship a different JDK, and that needs its own review rather than riding along on a derivation refactor
- [x] 1.8 Only once 1.6 confirms agreement, delete the `Derive installed Java major version` step in `update-version.yml` (`:296-303`) and `script/java_version.sh` (referenced only there)
- [x] 1.9 Confirm the task still succeeds on the `test-gradle` leg (`build.yml:494-498`), which appends the same script to a scratch `flutter create` app. That leg runs `cue vet` and ends (`:500-501`) — no `git diff`, so its mutation of `config/version.json` is discarded rather than compared. The regression risk is therefore only that the added Java derivation *throws* there, not that it writes a different value; verify the reflection resolves in that context, where the plugin arrives via the same composite included build.

  **This task was first marked done on structural reasoning alone, and that was wrong — the leg then failed on CI** with `null cannot be cast to non-null type org.gradle.api.JavaVersion`. `@VisibleForTesting` makes Kotlin emit `getErrorJavaVersion$gradle$annotations` next to the real getter: zero-arg, same name prefix, `static`, returning `void`. `Class.methods` order is unspecified, so the name-only filter could select the holder, and did there. Fixed by also filtering on the `JavaVersion` return type. The local harness missed it because the mimicked declaration omitted `@VisibleForTesting`, so no holder was generated — a reflection harness must reproduce the *annotations* of the target, not just its types. Now genuinely verified: `Test Gradle` passes on PR #537

## 2. Floor assertion (design D5)

- [x] 2.1 Add `check(JavaVersion.current().majorVersion.toInt() >= javaMajor)` to `script/updateAndroidVersions.gradle.kts`, reusing the value derived in group 1 rather than a literal, with a failure message naming the required minimum
- [x] 2.2 Place the assertion between the derivation (group 1) and the `jsonFile.writeText` at `script/updateAndroidVersions.gradle.kts:50`, so a below-floor JDK fails before `config/version.json` is mutated. The natural place to add the `newJsonMap` entry in task 1.4 is adjacent to that write — the assertion must precede it, not merely follow the derivation

## 3. Dockerfile follows the manifest (design D4)

- [x] 3.1 Declare `ARG android_java_version` above the `ENV` block at `android.Dockerfile:139-140`. Written as "move ... it currently sits at ~:176" — that was wrong: no such ARG existed. The `:176` block holds the other four android args (`android_build_tools_version`, `android_platform_versions`, `android_ndk_version`, `cmake_version`), all declared after the `ENV` because none is consumed by it. This one must precede the `ENV`, so it is declared at `:139` rather than joining them
- [x] 3.2 Change `JAVA_HOME` to `"/usr/lib/jvm/java-${android_java_version}-openjdk-amd64"`
- [x] 3.3 Change the apt install at `:164` to `"openjdk-${android_java_version}-jdk-headless=$OPENJDK_17_JDK_HEADLESS_VERSION"`, leaving the `# renovate:` annotation and the `ARG OPENJDK_17_JDK_HEADLESS_VERSION` declaration untouched
- [x] 3.4 Export the value from `script/setEnvironmentVariables.js`: `core.exportVariable('ANDROID_JAVA_VERSION', data.android.java.version)`, alongside the eleven existing exports. This is the edit that makes `${{ env.ANDROID_JAVA_VERSION }}` resolve — without it the build-arg lines in 3.5 expand to empty. Skip only if `manifest-build-arg-wiring` has landed and a table row covers it
- [x] 3.5 Add `android_java_version=${{ env.ANDROID_JAVA_VERSION }}` to each of the four build-args blocks: `build.yml:158-164` (push path), `build.yml:180-186` (fork path), `ci.yml:84-90`, `release.yml:114-120`. One table row instead, if the wiring change landed
- [x] 3.6 Note that `build.yml:156-157` and `release.yml:112-113` are shared android/web blocks — the comment there says the android args "are inert for the web target (its stage declares none of them)". `android_java_version` joins them on the same terms: BuildKit emits an `UnusedBuildArgs` warning on the web leg, as it already does for the other six. If that warning is unwanted, split the blocks — but that is a pre-existing condition, not something this change introduces

## 4. Verification

Cheap and local: 4.1, 4.2, 4.5, 4.6. The rest need a built image and are CI-verified
if a local build is impractical.

- [x] 4.1 `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- [x] 4.2 `script/update_test.sh` regenerates `test/android.yml` with no diff (fixed point)
- [x] 4.3 **CI-verified** — a local build is impractical here (the first stage, `flutter`, dies on a TLS-intercepting certificate blocking the Dart SDK download; unrelated to this change and upstream of the `android` stage it touches). `container-structure-test` passes `test/android.yml`, including the "Java is pinned" assertion — the primary image check, which subsumes inspecting `JAVA_HOME` because it asserts the runtime `java -version` major. Confirmed green on PR #537: `Test image (flutter-android)` pass, alongside `Test Gradle` pass
- [x] 4.4 Confirm `docker inspect` shows no `*_VERSION` apt-package pin in the image's `Env` — neither as a literal nor interpolated into another value. This is the checkable form of the modified `linux-image-package-pinning` requirement; `JAVA_HOME` is expected in `Env` and is not a pin. Verified on a standalone image reproducing the same ARG/ENV shape: `Env` held `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` and `ANDROID_HOME`, no pin. Structurally guaranteed too — `OPENJDK_17_JDK_HEADLESS_VERSION` is consumed only inside the `RUN`, never assigned to an `ENV`
- [x] 4.5 Confirm Renovate's regex still matches the openjdk ARG — run `script/renovate_validate.sh` and check the annotation/ARG pair at `android.Dockerfile:144-145` is unchanged. Config validates; `git diff main -- android.Dockerfile` touches neither line, so the manager matches the same pair
- [x] 4.6 Grep `android.Dockerfile` for literal `17`. Expected hits, and no others: the patch pin default and its ARG name (`:145`), the `# renovate:` annotation's `depName` (`:144`), and the two bookworm-repository prose comments (`:150`, `:169`). The two that must disappear are `JAVA_HOME` (`:141`) and the apt package name (`:165`) — both confirmed gone. Line numbers shifted by one from the pre-change file when `ARG android_java_version` was inserted at `:139`

## 5. Wrap-up

- [x] 5.1 Replace the three `moby/moby#29110` TODO comments at `android.Dockerfile:136-138` with a one-line note that the value now arrives as a build argument. They asked for *runtime* discovery via `readlink`, which moby#29110 still blocks — so they are obsoleted by a different route, not resolved, and deleting them without a note would read as a claim that runtime discovery works. Comment-only, no behaviour change, so it sits outside group 3's revert surface
- [x] 5.2 (gmeligio/flutter-docker-image#537) Open the PR with a Conventional Commit title, one logical concern
- [x] 5.3 Note in the PR that `config/version.json` is intentionally unchanged, and why (both sources yield 17)
- [x] 5.4 (gmeligio/flutter-docker-image#534) Open a GitHub issue for the deferred cleanup recorded in research F10: nine dead scripts, the `cmdlineTools` mirror, the dead `30.0.3` job-env lines
- [x] 5.5 (gmeligio/flutter-docker-image#535) Open a GitHub issue for the PR-body annotation wording: `update-version.yml:428-431` says "Android toolchain unchanged this cycle" whether the producer skipped or failed. Distinguishing the two applies to all three platform producers, so it belongs in its own change (design Observability)
- [x] 5.6 (gmeligio/flutter-docker-image#536) Open a GitHub issue for the major-bump rename coupling: when Flutter's floor moves to 21, `android_java_version` becomes 21 while the pin is still named `OPENJDK_17_JDK_HEADLESS_VERSION` with a bookworm-suite annotation. The "Java is pinned" assertion does not catch a stale patch pin under a renamed major
- [x] 5.7 On archive, correct the main spec's experience context for *"Android producer derives the installed Java major version"* (`openspec/specs/flutter-version-update/spec.md:192`), which names "the CI engineer reading the README's Java version" — the README has never mentioned Java. The delta already replaces that context; this is the sync the project's archive rule requires
