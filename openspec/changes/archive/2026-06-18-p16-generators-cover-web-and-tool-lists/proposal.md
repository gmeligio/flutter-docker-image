## Why

`p15` (this PR, not yet merged) replaced the MDX docs toolchain with code
generation: `docs/build.mjs` generates `readme.md` and `docs/examples.cue`
generates `examples/*.yml`, both from `config/version.json`. While that work was
in review, `main` advanced six commits that **hand-edit the very `readme.md`
`p15` now generates** and add a whole new image:

- **flutter-web image** (#489) — new `web` target, `web-image-release` /
  `web-image-testing` specs, `test/web.yml`, and a second published Linux image.
- **README per-image "Main tools" lists** (#503) — the `image-tool-inventory`
  capability: a curated tool list per image, with a newly-tracked
  `config/version.json` `android.java.version: 17`.
- **Dropped the standalone Fastlane usage block** (#505); Fastlane is now one
  line in the android tool list.
- **`build.yml` `build-image` → matrix** (android + web from `android.Dockerfile`
  targets); a `contributing.md` fix (#507); Flutter `3.44.2 → 3.44.4` (#504/#508).

The result is a conflict that is **conceptual, not textual**: `main` evolved the
README into a **two-image** document by hand, while `p15` makes it generated and
single-image. Three files conflict (`readme.md`, `config/version.json`,
`docs/contributing.md`; `build.yml` likely auto-merges — disjoint job regions),
and — critically — `main`'s `image-tool-inventory` spec says its tool lists are
sourced "through `docs/src/content.mdx`", the MDX file `p15` deletes.

This change is justified for a spec because it changes what the reader sees (the
generated README must now reproduce `main`'s two-image content, including the
Java-tracked tool lists) and reconciles two overlapping capabilities so they
don't contradict: `image-tool-inventory` (the README *content* contract) and
`generated-docs-and-examples` (the *generation* contract).

## What Changes

- **Merge `origin/main`** into the branch. Take `main` wholesale for: the
  flutter-web image and its specs, `test/web.yml`, `config/version.json`
  (`3.44.4` + `android.java.version`), the `build.yml` `build-image` matrix, and
  the `contributing.md` text — while keeping `p15`'s `build-docs → mise run docs`
  edit and its deletion of `docs/src/`.
- **Extend `docs/build.mjs`** to reproduce `main`'s current `readme.md`:
  - **Two images** — flutter-android **and** flutter-web: web badges, a
    flutter-web Running Containers table, and a flutter-web usage example.
  - **Per-image "Main tools" lists** satisfying `image-tool-inventory`:
    android = Flutter, Java (OpenJDK, from `android.java.version`), Android SDK
    Platform, Android NDK, Gradle, Fastlane; web = Flutter + "web engine
    precached, no runtime download". Dart and Android Build Tools intentionally
    excluded.
  - **No standalone Fastlane usage block** (matches #505).
- **`docs/contributing.md`** stays static (its `p15` posture) but carries
  `main`'s #507 text, with the stale auto-gen banner stripped.
- **Reconcile specs (both MODIFIED, none new):**
  - `image-tool-inventory` — re-point the mechanism clauses from
    `docs/src/content.mdx` / "generated from `docs/src`" to **`docs/build.mjs`
    reading `config/version.json`**. The *content* requirements (which tools per
    image, Java from manifest, Dart/Build-Tools excluded) are unchanged.
  - `generated-docs-and-examples` (created by `p15`) — extend from one image to
    **two**, and state that the generated README's content is exactly what
    `image-tool-inventory` requires.
  - Check `flutter-version-update` for any `docs/src` reference introduced by
    `main` and re-point it if present.
- **`docs/examples.cue`** — keep the four per-CI-backend example files (they use
  the primary `flutter-android` image). A flutter-web example is **optional /
  out of scope** here unless trivial.
- **No image change beyond what `main` already shipped.** `config/version.json`
  remains the single source, CUE-validated.

## Capabilities

### Modified Capabilities

- `image-tool-inventory`: mechanism re-pointed to `docs/build.mjs` (content
  contract unchanged).
- `generated-docs-and-examples`: extended to the two-image README, including the
  per-image tool lists and Java version.

## Impact

- **Affected**: `docs/build.mjs` (extended), `config/version.json` (from main),
  `docs/contributing.md` (main text, static), `.github/workflows/build.yml`
  (merge), plus everything `main` adds (web image, `test/web.yml`, web specs).
- **Depends on**: this PR carrying `p15` (the generators it extends).
- **Risk**: the new parity target is `main`'s two-image `readme.md` — verify by
  regenerating and diffing against `main`'s committed `readme.md` (must match at
  `3.44.4`). The hand-rolled TOC must still produce correct anchors for the new
  web headings.
- **Risk**: spec overlap — if `image-tool-inventory` and
  `generated-docs-and-examples` are not reconciled, they contradict on the
  generation mechanism. Resolved by the MODIFIED specs above.
- **Out of scope**: a flutter-web entry in `examples/`; any change to the web
  image itself (owned by #489 / `web-image-release`).
