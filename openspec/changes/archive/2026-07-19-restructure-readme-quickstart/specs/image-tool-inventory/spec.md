## REMOVED Requirements

### Requirement: README lists main tools and versions per published image

**Reason**: The README is being restructured into a concise quick-start where the
above-the-fold content is what-is / how-to-use. The per-image main-tool tables
(Java, Android SDK Platform, NDK, Gradle, Fastlane, web-engine line) are reference
data, not onboarding, and pushed the first usage snippet a third of the way down
the page. Removing them is a deliberate scope reduction: the README no longer
renders per-image tool inventories.

**Migration**: The Flutter SDK version — the one version a reader needs to pin an
image — remains stated in the README prose (and in the version badge). The exact
versions of the other tools an image ships are discoverable from the image itself
(`docker run <image>:<tag> flutter doctor -v`, `java -version`, etc.) and from the
pinned values in `config/version.json`, which remains the single source of truth
validated by `config/schema.cue`. No published image or tag changes; only the
README presentation is reduced. The `generated-docs-and-examples` capability
continues to require the README to state the manifest Flutter version.
