## Why

The Renovate custom manager that bumps the Debian apt-package version pins in `android.Dockerfile` matches **zero files** and has done so since the `Dockerfile → android.Dockerfile` rename in #317. Its `managerFilePatterns` is `/^Dockerfile$/`, an anchored regex that requires a file named exactly `Dockerfile` at the repo root — which no longer exists. As a result, nine apt pins (curl, git, lcov, ca-certificates, unzip, ruby-dev, build-essential, openjdk-17-jdk-headless, sudo) silently receive no automated updates and only move when bumped by hand. This is a spec-worthy change because it defines an observable contract a CI engineer relies on — "the image's apt package versions are kept current automatically" — that is currently broken with no signal.

## What Changes

- Fix `.github/renovate.json` `managerFilePatterns` for the `deb` custom manager from `/^Dockerfile$/` to the glob `**/*.Dockerfile`, so the manager matches `android.Dockerfile` (and any future `*.Dockerfile`) regardless of rename.
- Normalize two stray version pins in `android.Dockerfile` from `ENV` to `ARG` (`BUILD_ESSENTIAL_VERSION`, `BUNDLER_VERSION`), establishing a single keyword convention: every self-pinned `*_VERSION` value is an `ARG`. This keeps the `matchStrings` regex strict (`ARG`-only) and removes a build-only value from the final image's runtime environment and metadata, where it does not belong and could collide with a real env var (`bundler` reads `BUNDLER_VERSION`).
- The lowercase/uppercase `ARG` split is intentional and is preserved: UPPERCASE-with-default = self-pinned, Renovate-managed; lowercase-no-default = injected at build time via `--build-arg` from CI. Casing is irrelevant to Renovate's matching.

## Capabilities

### New Capabilities
- `linux-image-package-pinning`: How the Linux (`android.Dockerfile`) image's Debian apt-package versions are pinned and kept current — the `# renovate:`-annotated `ARG *_VERSION` convention, the `deb`-datasource custom manager that must match the Dockerfile, and the invariant that no managed pin is declared with `ENV`.

### Modified Capabilities
<!-- None. Existing renovate coverage in `actions-version-tracking` is about GitHub Actions via gx.toml — a separate manager and datasource. No existing spec covers the image's apt pins. -->

## Impact

- `.github/renovate.json` — one-line `managerFilePatterns` fix for the `deb` custom manager.
- `android.Dockerfile` — two declarations change `ENV` → `ARG` (lines 99, 122). No behavioral change: both values are consumed at build time on the next line and read by nothing else.
- No change to `matchStrings`, casing, `windows.Dockerfile` (no `# renovate:` apt pins), or the `gx.toml` action manager.
- After the fix, the next weekly Renovate run can open PRs against the nine apt pins for the first time.
