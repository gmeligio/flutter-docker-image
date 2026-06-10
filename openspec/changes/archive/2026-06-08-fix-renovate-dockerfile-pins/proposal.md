## Why

The Renovate custom manager that bumps the Debian apt-package version pins in `android.Dockerfile` matches **zero files** and has done so since the `Dockerfile → android.Dockerfile` rename in #317. Its `managerFilePatterns` is `/^Dockerfile$/`, an anchored regex that requires a file named exactly `Dockerfile` at the repo root — which no longer exists. As a result, nine apt pins (curl, git, lcov, ca-certificates, unzip, ruby-dev, build-essential, openjdk-17-jdk-headless, sudo) silently receive no automated updates and only move when bumped by hand. This is a spec-worthy change because it defines an observable contract a CI engineer relies on — "the image's apt package versions are kept current automatically" — that is currently broken with no signal.

## What Changes

- Fix `.github/renovate.json` `managerFilePatterns` for the `deb` custom manager from `/^Dockerfile$/` to the glob `**/*.Dockerfile`, so the manager matches `android.Dockerfile` (and any future `*.Dockerfile`) regardless of rename.
- Normalize two stray version pins in `android.Dockerfile` from `ENV` to `ARG` (`BUILD_ESSENTIAL_VERSION`, `BUNDLER_VERSION`), establishing a single keyword convention: every self-pinned `*_VERSION` value is an `ARG`. This keeps the `matchStrings` regex strict (`ARG`-only) and removes a build-only value from the final image's runtime environment and metadata, where it does not belong and could collide with a real env var (`bundler` reads `BUNDLER_VERSION`).
- The lowercase/uppercase `ARG` split is intentional and is preserved: UPPERCASE-with-default = self-pinned, Renovate-managed; lowercase-no-default = injected at build time via `--build-arg` from CI. Casing is irrelevant to Renovate's matching.
- Correct two wrong `depName` annotations uncovered while fixing the manager: `RUBY_VERSION` named `ruby-dev` but installs `ruby-full`; `BUNDLER_VERSION` named `fastlane` (refactor residue) but installs `bundler`. A wrong `depName` tracks the wrong package — worse than an unmatched pin — so these are in scope.
- Add a rubygems custom manager to `.github/renovate.json` so the (now correctly named) `bundler` pin is actually updated; previously no manager matched `datasource=`-style inline comments, leaving it dead. `fastlane` is deliberately left unmanaged here — its version is owned by `config/version.json` and fanned out to the build and docs, so an inline pin would be wrong and redundant.

## Capabilities

### New Capabilities
- `linux-image-package-pinning`: How the Linux (`android.Dockerfile`) image's Debian apt-package versions are pinned and kept current — the `# renovate:`-annotated `ARG *_VERSION` convention, the `deb`-datasource custom manager that must match the Dockerfile, and the invariant that no managed pin is declared with `ENV`.

### Modified Capabilities
<!-- None. Existing renovate coverage in `actions-version-tracking` is about GitHub Actions via gx.toml — a separate manager and datasource. No existing spec covers the image's apt pins. -->

## Impact

- `.github/renovate.json` — `managerFilePatterns` fix for the `deb` custom manager, plus a new rubygems custom manager for inline `datasource=rubygems` gem pins.
- `android.Dockerfile` — two declarations change `ENV` → `ARG` (lines 99, 122; no behavioral change, both consumed at build time on the next line), and two `depName` annotation corrections (`ruby-dev` → `ruby-full`, `fastlane` → `bundler`).
- No change to the deb `matchStrings`, casing, `windows.Dockerfile` (no `# renovate:` apt pins), the `gx.toml` action manager, or the `fastlane`/`config/version.json` manifest mechanism.
- After the fix, the next weekly Renovate run can open PRs against the nine apt pins (now correctly named) and the `bundler` gem for the first time.
