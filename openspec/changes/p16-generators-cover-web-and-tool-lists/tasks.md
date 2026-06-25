## 1. Merge main

- [ ] 1.1 Merge `origin/main` into the branch.
- [ ] 1.2 Resolve `config/version.json` → take `main` (`3.44.4` +
  `android.java.version: 17`).
- [ ] 1.3 Resolve `.github/workflows/build.yml` → take `main`'s `build-image`
  matrix (android + web); keep `p15`'s `build-docs` step (`mise run docs`) and
  the `examples/` upload. Confirm `docs/src` stays deleted.
- [ ] 1.4 Resolve `docs/contributing.md` → take `main`'s #507 text; keep it
  static; strip the stale auto-gen banner.
- [ ] 1.5 Accept `main`'s additions verbatim: flutter-web image, `test/web.yml`,
  `web-image-release` / `web-image-testing` / `image-tool-inventory` specs.
- [ ] 1.6 `readme.md` conflict → leave for regeneration in §2 (do not hand-merge).

## 2. Extend `docs/build.mjs` to the two-image README

- [ ] 2.1 Read `android.java.version` from `config/version.json`.
- [ ] 2.2 Render flutter-web alongside flutter-android: web badges
  (`docker/v` + `docker/pulls` for `flutter-web`), a flutter-web Running
  Containers table, and a flutter-web GitHub Actions usage example.
- [ ] 2.3 Render per-image **Main tools** lists per `image-tool-inventory`:
  android = Flutter, Java (OpenJDK), Android SDK Platform, Android NDK, Gradle,
  Fastlane; web = Flutter + "web engine precached, no runtime download". Exclude
  Dart and Android Build Tools.
- [ ] 2.4 Remove the standalone Fastlane usage block (matches #505).
- [ ] 2.5 Regenerate: `mise run docs`; confirm `git diff readme.md` against
  `main`'s committed `readme.md` is **empty** at `3.44.4` (parity), and that
  regeneration is idempotent.

## 3. Reconcile specs

- [ ] 3.1 Apply the `image-tool-inventory` modification (mechanism →
  `docs/build.mjs`; content unchanged).
- [ ] 3.2 Apply the `generated-docs-and-examples` modification (two images +
  Main-tools content + Java).
- [ ] 3.3 Check `flutter-version-update` (and any other spec) for a `docs/src`
  reference introduced by `main`; re-point to `docs/build.mjs` if present.

## 4. Verify

- [ ] 4.1 `mise run docs` → `git diff --exit-code` clean over `readme.md` +
  `examples/` (the in-sync gate).
- [ ] 4.2 All `examples/*.yml` valid YAML at the current tag; the four backend
  files unchanged in shape.
- [ ] 4.3 Flip `android.java.version` in a scratch manifest → the rendered Java
  line changes (image-tool-inventory satisfied).
- [ ] 4.4 Push; confirm CI (docs-in-sync, build matrix, gx, web tests) is green.

## 5. Archive

- [ ] 5.1 After merge, sync the MODIFIED `image-tool-inventory` and
  `generated-docs-and-examples` specs to shipped behavior and move this change to
  `openspec/changes/archive/<YYYY-MM-DD>-p16-generators-cover-web-and-tool-lists/`.
