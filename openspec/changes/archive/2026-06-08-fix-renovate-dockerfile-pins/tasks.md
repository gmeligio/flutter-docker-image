## 1. Fix the Renovate file pattern

- [x] 1.1 In `.github/renovate.json`, change the deb custom manager's `managerFilePatterns` from `["/^Dockerfile$/"]` to `["**/*.Dockerfile"]`
- [x] 1.2 Run `script/renovate_validate.sh` and confirm the config remains schema-valid

## 2. Normalize stray version pins to ARG

- [x] 2.1 In `android.Dockerfile`, change `ENV BUILD_ESSENTIAL_VERSION="…"` (line ~99) to `ARG BUILD_ESSENTIAL_VERSION="…"`
- [x] 2.2 In `android.Dockerfile`, change `ENV BUNDLER_VERSION="…"` (line ~122) to `ARG BUNDLER_VERSION="…"`
- [x] 2.3 Confirm both values are still referenced only on their immediately-following line (`grep -n BUILD_ESSENTIAL_VERSION android.Dockerfile script/`, same for `BUNDLER_VERSION`) — no `ENV`-scoped runtime consumer

## 3. Verify the manager now matches

- [x] 3.1 Run a local Renovate dry-run (`npx renovate --platform=local`, `LOG_LEVEL=debug`) and grep the log for `android.Dockerfile` plus the extracted deb depNames — log shows `Matched 2 file(s) for manager regex: android.Dockerfile, windows.Dockerfile` (was zero before)
- [x] 3.2 Confirm all nine apt pins (curl, git, lcov, ca-certificates, unzip, ruby-dev, build-essential, openjdk-17-jdk-headless, sudo) are extracted as `deb` dependencies — i.e. the manager matches nine pins, not zero — all nine confirmed extracted, including `build-essential` (the former `ENV` pin)
- [x] 3.3 Build the Linux image and confirm via `docker inspect` that no `*_VERSION` apt pin appears in the image `Env` config (the `ENV → ARG` change took effect) — full-image build is blocked by a pre-existing stale `curl` pin (the very staleness this change fixes; Renovate must bump it first). Verified the `ENV → ARG` property in isolation: a minimal image reproducing the exact `ARG …_VERSION="…"` declarations shows no `*_VERSION` key in `.Config.Env` (only `PATH`). The pins stay build-time-only.

## 3b. Correct annotation depNames and datasource wiring

- [x] 3b.1 Fix `RUBY_VERSION` annotation `depName=ruby-dev` → `ruby-full` (the package the `RUN` actually installs)
- [x] 3b.2 Fix `BUNDLER_VERSION` annotation `depName=fastlane` → `bundler` and drop the redundant `versioning=ruby` (rubygems default); the line installs `bundler`, not `fastlane`
- [x] 3b.3 Add a rubygems custom manager to `.github/renovate.json` matching `# renovate: datasource=… depName=… ARG …_VERSION="…"`, so the bundler pin is live (was dead — no manager matched `datasource=` comments)
- [x] 3b.4 Dry-run verify: deb set now includes `ruby-full` (not `ruby-dev`); `bundler` is extracted as a `rubygems` dep and yields an update; `fastlane` appears as zero Renovate deps (it stays manifest-managed via `config/version.json`)

## 4. Wrap up

- [x] 4.1 Open the change as a single small PR titled `fix(renovate): match android.Dockerfile for Debian package pins` — PR #488 (draft, via Graphite)
- [x] 4.2 Note the CI dry-run guard (assert ≥1 deb dependency extracted) as a follow-up in the PR description, per design Non-Goals
