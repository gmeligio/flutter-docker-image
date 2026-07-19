## 1. Relocate reference/contributor content (static markdown)

- [ ] 1.1 Append a "Building locally" section to `docs/contributing.md` with the Android and Windows `docker build` invocations (keep the version literal/illustrative, not manifest-interpolated).
- [ ] 1.2 Create `docs/faq.md` with the two existing FAQ entries (why no AWS ECR Public registry; why no dynamic `:latest` tag), preserving the current wording and links.

## 2. Rewrite the generator badges (`docs/build.mjs`)

- [ ] 2.1 Replace the two `dockerBadge(..., 'version', ...)` callers with a single Flutter version badge: `static/v1`, `label=version`, `message=${flutter}`, linked to the Flutter release archive.
- [ ] 2.2 Add a `flutter-windows` pulls badge alongside `flutter-android` and `flutter-web`, so the row is: scorecard, deepwiki, channel, version, android pulls, web pulls, windows pulls.

## 3. Rewrite the generator body (`docs/build.mjs`)

- [ ] 3.1 Remove the `toc()` function and its invocation, and the `## Contents` section.
- [ ] 3.2 Rewrite the top of the body to a quick-start: one-line description + copy-paste `docker run` above the fold; state the manifest Flutter version in prose.
- [ ] 3.3 Remove the per-image "Main tools" lists (Java, Android Platform, NDK, Gradle, Fastlane, web-engine line) from the Features section; keep a short platform list naming android/web/windows.
- [ ] 3.4 Add a `flutter-windows` Running Containers registry table via `registryTable('flutter-windows')`.
- [ ] 3.5 Add a Windows usage snippet using `runs-on: windows-2025` (not the Linux `container:` pattern); do not route Windows through `ghWorkflow()`.
- [ ] 3.6 Collapse the four inline per-backend CI snippets to one GitHub Actions example; keep all four platform names and the `examples/` link.
- [ ] 3.7 Remove the `## Roadmap` section.
- [ ] 3.8 Remove the inline `## Building Locally` and `## FAQ` sections; add README links to `docs/contributing.md` (Building locally) and `docs/faq.md`.

## 4. Regenerate and verify

- [ ] 4.1 Run `mise run docs` and commit the regenerated `readme.md`.
- [ ] 4.2 Confirm `git diff --exit-code` is clean after a second `mise run docs` (drift gate).
- [ ] 4.3 Inspect `readme.md`: version stated in prose; android/web/windows sections each present with one pulls badge; no TOC, no tool table, no Roadmap; links to `docs/faq.md` and `docs/contributing.md` resolve.
- [ ] 4.4 Verify the Windows snippet is faithful to how `flutter-windows` is actually pulled/run (documentation-only, but correct).

## 5. Spec sync (at archive)

- [ ] 5.1 On archive, sync `generated-docs-and-examples` to the shipped README shape and remove the `image-tool-inventory` capability from `openspec/specs/`.
