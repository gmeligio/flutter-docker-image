## Context

`config/version.json` is the single committed source of truth for the pinned toolchain, validated by `config/schema.cue` (`cue vet -d '#Version'`). It is mutated only by the three producer jobs in `update-version.yml`, then overlaid by `compose-and-open-pr`:

- `update-flutter-version` → `.flutter = {…}` (full replace)
- `update-windows-version` → `.windows = {…}` (full replace)
- `update-android-version` → emits `{android, fastlane}`; the `android` block is written by `script/updateAndroidVersions.gradle.kts` (a `putAll` of `platforms, gradle, buildTools, ndk`) plus `script/updateFastlaneVersion.js`.

Two existing `android` sub-fields — `cmake` and `cmdlineTools` — are **not** written by the gradle producer; they survive by being carried forward (the gradle `putAll` only touches its four keys, and the composer's `. + $android_block` replaces `.android` with the producer's copy, which still contains them). Java would be a third such field.

`docs/src/content.mdx` already injects every displayed version from `version.json` exports (`flutterVersion`, `gradleVersion`, `androidNdkVersion`, …), so the README cannot drift from the manifest. Java is the gap: it is pinned only in `android.Dockerfile` (`openjdk-17-jdk-headless`, `java-17-openjdk-amd64`) and absent from `version.json`, so it cannot be shown without a hand-written copy. A `script/java_version.sh` helper (`java -version | awk … → 17`) already exists but is currently unused.

The web image's value is the precached web engine (`flutter precache --web`); since the engine/framework monorepo merge (Flutter 3.27, [3.32 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.32.0)) the engine builds from the same commit as the framework, so there is no human-meaningful "web engine version" distinct from the Flutter SDK already listed.

## Goals / Non-Goals

**Goals:**
- README shows, per published Linux image, the main tools and the exact versions that image ships.
- The Java version is shown and equals the JDK actually installed in the image (no drift, no second hand-maintained pin).
- All displayed versions remain sourced from `config/version.json`.

**Non-Goals:**
- Tracking the Dart SDK version (bundled with Flutter; not separately pinned).
- Showing Build Tools / CMake / Command-line Tools in the main tools list (deliberately curated down).
- Parameterizing the Dockerfile's JDK **major** from `version.json` (the Debian package name stays the install source; `version.json` mirrors it).
- A matrix/combined table or a third Windows column (per-image lists chosen for clarity; Windows is a separate-OS toolchain).

## Decisions

### Decision 1: Java lives at `android.java.version`, nested under `android`
Java is installed only in the `android` image, so it is scoped under the `android` block — not top-level. There it behaves exactly like the existing `cmake` / `cmdlineTools` sub-fields: the gradle `putAll` does not touch it, so it is never clobbered, and the composer carries it forward on the Android-skip path with the rest of the `android` block.

- **Alternative rejected — top-level `.java`:** also survives the producers (none touch it), but misrepresents scope — Java is an Android-image tool, not a manifest-wide one, and `flutter-web` ships no JDK.

### Decision 2: Model the value as a positive-integer major
`android.java.version` is the **major** only (e.g. `17`), modeled like `android.platforms[].version` (a bare int via `#PlatformVersion`). The full patch (`17.0.19+…`) stays in the Dockerfile ARG (Renovate-managed); the README's main tools list shows the friendly major, and an int is the simplest schema shape that `cue vet` can enforce.

- **Alternative rejected — full semver-quad string:** more precise but not what the main tools list shows, and it would duplicate the Renovate-managed patch with a second update path.

### Decision 3: Derive Java from the live container, not a static pin
The `update-android-version` job already runs inside the released `flutter-android` image and derives `gradle`/`ndk`/`buildTools` from real tools. Add a step that runs `script/java_version.sh` there to read the installed JDK major and write `android.java.version` via `jq`. This keeps `version.json` a mirror of reality rather than a hand-maintained duplicate of the Dockerfile's `openjdk-17` pin — on-brand with the repo's "derive from the artifact" pattern, and it reuses an existing-but-unused helper.

- **Alternative rejected — static hand-pinned `17`:** simplest, but creates a second independent pin of the Java major (Dockerfile + manifest) that can silently disagree — exactly the drift the README change is trying to avoid. `cmake`/`cmdlineTools` are single-source (`version.json → build-arg → Dockerfile`); a static Java would be the only dual-pinned value.
- **Accepted lag:** the producer runs the *last released* image, so a Java **major** bump (a deliberate manual Dockerfile edit) shows up one cycle late. Mitigation: set `android.java.version` in the same PR that bumps the Dockerfile; the producer re-confirms it next cycle. Java majors change rarely.

### Decision 4: Web engine shown as a precache guarantee, not a version
The `flutter-web` list shows the Flutter SDK version and the qualitative line "Web engine — precached (no runtime download)" — no fabricated engine version. The Flutter SDK version already fully determines the engine in the monorepo era; inventing a separate number would be misleading.

### Decision 5: Two per-image lists; Dart and Build Tools excluded
The README gets one main tools list per image (android, web) rather than a combined matrix — clearest for the two-image case and matches the existing per-image Running-Containers layout. Dart (bundled, untracked) and Build Tools (not a main tool for image selection) are intentionally omitted, per the curated set agreed during exploration.

## Automated Test Strategy

- **Critical path:** the Java version the README shows equals the JDK the image ships. Two complementary mechanisms guarantee this: (a) the value is **derived** from the running container (`script/java_version.sh`) and **displayed** from the same `version.json` field, so README ↔ manifest cannot diverge by construction; and (b) a `test/android.yml` structure test asserts the **built** image's `java -version` major equals `android.java.version`, so manifest ↔ image is machine-checked at build time (a Dockerfile JDK-major bump not reflected in the manifest fails the PR's `build.yml` test leg). Together these close README ↔ manifest ↔ image.
- **Schema gate (existing, now covers Java):** `cue vet config/schema.cue -d '#Version' config/version.json` runs in every producer self-validation step, the `compose-and-open-pr` gate, and `build.yml`'s version-file validation. With `java!` added to `#Version.android`, a missing or non-integer `android.java` turns these red — so a malformed Java field cannot reach a PR or a merge.
- **Producer self-validation:** if `java_version.sh` yields a non-integer (e.g. unexpected `java -version` format), the `jq` write produces a value `cue vet` rejects, failing the `update-android-version` job *before* it emits `android_block`; the empty output then carries forward the base `android.java` (no corruption propagates) — the same safety pattern the spec already defines for the other android fields.
- **Docs sync (existing):** `mise run docs` regenerates `readme.md`; the `update-docs` check fails the PR if `content.mdx` changed without a regenerated `readme.md`, catching a stale main tools list.
- **Built-image assertion:** `test/android.yml` gains a "Java is pinned" `container-structure-test` command test (`java -version 2>&1 | awk … → major`, `expectedOutput: [<android.java.version>]`), templated from a new `android_java_version` tag in `config/android.cue` and fed by `script/update_test.sh` — exactly like the existing build-tools / NDK assertions. It runs against the freshly built image in `build.yml`, so it fails the PR if the image's JDK major differs from the manifest. The `validate-generated-config` job keeps the committed `test/android.yml` a fixed point of regeneration (no drift).
- **Level:** no unit tests apply (config + docs + a CI step); integration is the schema gate, the docs-sync check, and the regenerated structure test described above.

## Observability

- **Malformed/missing Java surfaces loudly and is attributed:** `cue vet` failures name the offending producer (`update-android-version`) in the Actions tab, not a downstream schema blame — consistent with the existing "producers validate their own block" requirement.
- **No silent corruption:** a failed derivation empties `android_block`, and the composer carries forward the previously-validated base `android.java`; the PR body's existing "Android toolchain unchanged this cycle" annotation flags that the Android block (now including Java) was carried forward.
- **No silent doc drift:** the `update-docs` check makes "edited `content.mdx`, forgot to regenerate `readme.md`" a red check rather than a quietly stale README.
- **Diagnostic trail:** the `update-android-version` job log shows the `java -version` output the major was extracted from, so a wrong value is traceable to the exact source line.

## Risks / Trade-offs

- **One-cycle lag on a Java major bump** (Decision 3) → set `android.java.version` in the same manual PR that edits the Dockerfile's `openjdk-NN`; the next scheduled run re-confirms it. Low frequency, low impact.
- **`java_version.sh` parsing fragility across JDK builds** → output is validated by `cue vet` (must be an int); a parse miss fails the producer rather than writing a bad value. The helper already exists and targets the OpenJDK `java -version` format the image ships.
- **"Precached, no version" reads as vague to some users** (Decision 4) → accepted; it is the honest representation, and the Flutter SDK version (shown directly above) determines the engine.
- **Schema tightening rejects an old manifest lacking `android.java`** → the same PR adds the field to `version.json`, so the committed manifest satisfies the tightened schema; no historical manifest is validated by this gate.

## Migration Plan

1. Add `android.java.version` (current major, e.g. `17`) to `config/version.json` and `java!` to `#Version.android` in `config/schema.cue`; confirm `cue vet -d '#Version'` is green locally.
2. Add the Java-derivation step to `update-android-version` (reuse `script/java_version.sh`, write via `jq`); confirm the emitted `android_block` includes `android.java`.
3. Update `docs/src/content.mdx`: add the `javaVersion` export and the two per-image main tool lists (android + web); run `mise run docs` to regenerate `readme.md`.
4. Confirm the `update-docs` check and `build.yml` version-file validation stay green.

- **Rollback:** remove `java!` from the schema, `android.java` from `version.json`, the derivation step, and revert `content.mdx`; regenerate `readme.md`. No image content changes, so existing `flutter-android` / `flutter-web` images are unaffected.

## Open Questions

- None blocking. The optional `test/android.yml` Java assertion (requires `config/android.cue` templating changes) is deferred, not required for this change.
