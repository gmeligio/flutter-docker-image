## Why

`readme.md` opens with a table of contents, a feature list, and per-image tool
tables before the reader reaches a single `docker run` — the first usage snippet
is at line 58 of 162. The README doubles as the Docker Hub description for every
image, yet Windows — a fully published platform — is absent from it entirely (no
badge, no usage, no mention). A CI engineer landing here cannot pull an image in
under five seconds, and a Windows user sees nothing. This change makes the README
a concise what-is / how-to-use quick-start and promotes Windows to a first-class
platform. Breaking changes to the generated-docs and tool-inventory specs are in
scope; the README is a presentation surface, so restructuring it is a spec-level
behavior change that the relevance gate requires be captured as spec deltas.

## What Changes

- **Badge row**: replace the two per-image Docker `version` badges with a
  **single Flutter version badge** (all images share the manifest Flutter
  version), and render **one `pulls` badge per platform** — `flutter-android`,
  `flutter-web`, and **`flutter-windows`** (new). **BREAKING** to the badge
  contract in `generated-docs-and-examples`.
- **Windows as a first-class platform**: add `flutter-windows` to the platform
  list and Running Containers (registry table + a `runs-on: windows-2025` usage
  snippet, since Windows containers cannot use the Linux `container:` pattern).
- **Above the fold = what + how**: hoist a one-line description and the
  quick-start usage to the top. The Flutter version stays stated in README prose
  (not only in the badge).
- **Remove the generated table of contents**. **BREAKING** — the current spec
  mandates a TOC.
- **Remove the detailed per-image tool tables** (Java, Android Platform, NDK,
  Gradle, Fastlane, web-engine line). The Flutter SDK version remains in the
  README; the rest is not decision-relevant above the fold. **BREAKING** —
  retires the `image-tool-inventory` capability.
- **Relocate reference/contributor content** out of the README:
  - Building Locally → `docs/contributing.md` (static).
  - FAQ (no ECR, no `:latest`) → `docs/faq.md` (new static page), linked from
    the README.
  - Roadmap → **removed** (stale: it lists Windows as future though it ships;
    roadmap belongs in Issues/Milestones).
- Collapse the four inline per-backend CI snippets to one GitHub Actions example
  plus the existing link to `examples/`; the four platforms stay named.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `generated-docs-and-examples`: the README requirement changes shape — single
  Flutter version badge + one pulls badge per platform (incl. Windows); Windows
  added to platform list and Running Containers; the generated table of contents
  is removed; Building Locally and FAQ move to static `docs/` pages; the Flutter
  version is stated in README prose. Windows becomes a covered image alongside
  android and web.
- `image-tool-inventory`: **removed**. The README no longer renders per-image
  main-tool lists; only the Flutter SDK version is stated in prose. This
  capability's requirement is retired.

## Impact

- `docs/build.mjs`: badge array, body template, removal of the `toc()` function
  and its call, addition of `flutter-windows` rendering, removal of tool-list and
  Roadmap/FAQ/Building-Locally blocks.
- `readme.md`: regenerated (breaking layout change). Also the Docker Hub
  description for `flutter-android`, `flutter-web`, and (once issue #521 lands)
  `flutter-windows`.
- `docs/contributing.md`: gains the Building Locally section.
- `docs/faq.md`: new static page.
- `mise run docs` and the docs-in-sync CI check must pass with the new output.
- Related: issue #521 (windows Docker Hub description sync) — this change makes
  the synced README actually describe Windows.
