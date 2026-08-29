## Why

`android.Dockerfile` pinned `openjdk-17-jdk-headless` to `17.0.20+8-1~deb12u1`, a version
published in no Debian suite the image enables
([#555](https://github.com/gmeligio/flutter-docker-image/issues/555)). `main` could not
cold-build for three weeks.

Renovate stayed silent throughout, and that is worth recording but is not the failure: the pin
sorts *above* the archive ceiling under deb versioning, and Renovate only ever proposes
upgrades, so a pin ahead of the archive is indistinguishable to it from one that is current.

The actual failure was in review, not tooling. Editing a pin changes the Dockerfile, which
invalidates the build cache and re-runs `apt-get install` — so the image build **does** catch a
bad pin on the PR that introduces one. PR #529 stated "CI on this PR is the verification" and
was merged without that verification passing on the edited pin.

Repinning to the base-suite version `17.0.19+10-1~deb12u2` also fails: `bookworm-security`
carries `openjdk-17-jre-headless=17.0.20.1+1-1~deb12u1`, apt takes it as the candidate, and the
JDK's strict `Depends: openjdk-17-jre-headless (= <same version>)` forces the JDK to match. The
only installable version is the security one.

This meets the relevance gate: a CI engineer building these images is directly affected — the
image does not build — and where a pin resolves from is a property of the published images.

## What Changes

- **Repin** `OPENJDK_17_JDK_HEADLESS_VERSION` to `17.0.20.1+1-1~deb12u1`, the
  `bookworm-security` version, verified by a `--no-cache` build of the apt layer rather than by
  reading apt error output. Restores cold builds.
- **Drop the two `-updates` `registryUrls`** from `.github/renovate.json` and **keep the
  `-security` entries**, documenting in the `description` that Renovate cannot currently fetch
  them. Renovate hardcodes `const compression = 'gz'` and Debian publishes no `Packages.gz` on
  either, so all four 404 on every run — swallowed at debug level. But `-security` is where the
  only installable openjdk version lives, so removing it would make the config contradict where
  the pin comes from; `-updates` supplies no current pin. Blocked upstream on
  [renovate#44330](https://github.com/renovatebot/renovate/issues/44330) /
  [PR #35865](https://github.com/renovatebot/renovate/pull/35865).
- **Correct the `linux-image-package-pinning` spec**, whose experience context asserts that
  `17.0.20+8-1~deb12u1` was a real `bookworm-security` upload and has the two versions swapped.
  That exact version was not published anywhere; it appears to be an imprecise transcription of
  `17.0.20.1+1-1~deb12u1`, which is real — and that imprecision is what broke the build. The
  requirement also mandates resolving against `-updates` and `-security`, which no
  configuration can satisfy with current Renovate.

**No new CI check.** A dedicated pin-verification script was built and then removed: it
duplicated what the image build already does on the PR path, and its one non-duplicated case
(a pin rotting with no repo change) was judged not worth a scheduled job — finding that on the
next PR is the intended workflow.

**Not breaking.** No published image tag, entrypoint, or documented interface changes. The
repin moves the installed JDK to the version apt would actually select.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `linux-image-package-pinning`: Amends *"Each apt pin resolves against the same set of Debian
  suites the image enables"* — narrowing the mandate from base + `-updates` + `-security` (not
  satisfiable: four of six configured URLs cannot be fetched) to base + `-security`, requiring
  the unfetchable gap to be documented rather than silent, and correcting the experience
  context's false premise. Adds a scenario recording that the image build is what catches an
  uninstallable pin on its own PR.

## Impact

- `android.Dockerfile` — one `ARG` value (the repin).
- `.github/renovate.json` — remove two `-updates` `registryUrls` entries, expand two
  `description` fields. Per project convention this file changes only on a
  `renovate/reconfigure` branch, so it ships as its own PR.
- `openspec/specs/linux-image-package-pinning/spec.md` — amended requirement + corrected
  experience context.
- No workflow, script, or tooling changes. No change to image contents beyond the JDK version,
  and none to build cache keys, tags, or release flow.
