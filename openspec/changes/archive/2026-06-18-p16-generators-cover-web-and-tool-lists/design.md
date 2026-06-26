## Approach

Merge `main` for everything except the README/generators, then make the
generators reproduce `main`'s now-current two-image README. `main`'s committed
`readme.md` is the parity target.

```
  origin/main ──merge──▶ p15 branch
    ├─ take main:  version.json (3.44.4 + android.java), web image + specs,
    │              test/web.yml, build.yml build-image matrix, contributing.md text
    ├─ keep p15:   docs/build.mjs, docs/examples.cue, examples/*.yml,
    │              build.yml build-docs → mise run docs, docs/src deleted
    └─ extend:     docs/build.mjs → two-image README (parity with main's readme.md)
                        │ mise run docs
                        ▼
                   readme.md (generated) == main's two-image README @ 3.44.4
```

### Conflict resolution (the four files)

| File | Resolution |
|---|---|
| `config/version.json` | take `main` (`3.44.4` + `android.java.version: 17`) |
| `.github/workflows/build.yml` | take `main`'s `build-image` matrix; keep `p15`'s `build-docs → mise run docs` (disjoint jobs — likely auto-merges) |
| `docs/contributing.md` | take `main`'s #507 text; keep it static; strip the auto-gen banner |
| `readme.md` | not line-merged — **regenerated** from the extended `build.mjs` |

### `docs/build.mjs` changes (to hit parity)

- Read `android.java.version` from `config/version.json`.
- Render **two images**: flutter-android + flutter-web — web badges (`docker/v`,
  `docker/pulls` for `flutter-web`), a flutter-web Running Containers table, and a
  flutter-web GitHub Actions usage example.
- Render per-image **Main tools** lists exactly as `image-tool-inventory`
  requires: android = Flutter SDK, Java (OpenJDK), Android SDK Platform, Android
  NDK, Gradle, Fastlane; web = Flutter SDK + "web engine precached, no runtime
  download". Exclude Dart and Android Build Tools.
- Remove the standalone Fastlane usage block (#505).
- TOC unchanged in mechanism; it will pick up the new web headings
  automatically.

### Spec reconciliation

`image-tool-inventory` (content: *what tools per image*) and
`generated-docs-and-examples` (mechanism: *code-gen from version.json*) overlap
only on the word "how it's sourced". `main`'s `image-tool-inventory` says
"through `docs/src/content.mdx`" — now false. The MODIFIED specs:

- `image-tool-inventory`: swap the mechanism clauses to `docs/build.mjs` reading
  `config/version.json`. Content/exclusion requirements unchanged.
- `generated-docs-and-examples`: the README requirement extends to two images and
  states its content equals `image-tool-inventory`'s.

This keeps a single, non-contradictory story: `generated-docs-and-examples` is
the engine; `image-tool-inventory` is the content it must emit.

## Automated Test Strategy

- **Parity (decisive, pre-merge):** after merge + generator changes, run
  `mise run docs` and `git diff readme.md` against `main`'s committed `readme.md`
  — must be identical at `3.44.4` (the merge brings `main`'s `readme.md`; the
  regenerated one must reproduce it).
- **In-sync gate (CI):** `update-docs.yml` runs `mise run docs` then
  `git diff --exit-code` over `readme.md` + `examples/` — a generator that fails
  to reproduce the committed output fails the required check.
- **Idempotency:** re-running the generators yields no diff.
- **Examples validity:** `cue export` emits valid YAML; the four backend examples
  still reference the current tag.
- **Java sourcing:** flipping `android.java.version` in a scratch `version.json`
  changes the rendered Java line (satisfies `image-tool-inventory`).

## Observability

- `build.mjs` exits non-zero on a missing manifest field (e.g. `android.java`),
  so the new Java dependency fails loudly rather than rendering `undefined`.
- `mise run docs` aborts on the first failing command; the CI `git diff
  --exit-code` is the catch-all that blocks a stale or non-parity README from
  merging.
- The merge itself surfaces conflicts explicitly; the parity diff makes a
  silently-wrong regeneration impossible to miss (it would differ from `main`'s
  README).
