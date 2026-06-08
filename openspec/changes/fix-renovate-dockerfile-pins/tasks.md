## 1. Fix the Renovate file pattern

- [ ] 1.1 In `.github/renovate.json`, change the deb custom manager's `managerFilePatterns` from `["/^Dockerfile$/"]` to `["**/*.Dockerfile"]`
- [ ] 1.2 Run `script/renovate_validate.sh` and confirm the config remains schema-valid

## 2. Normalize stray version pins to ARG

- [ ] 2.1 In `android.Dockerfile`, change `ENV BUILD_ESSENTIAL_VERSION="…"` (line ~99) to `ARG BUILD_ESSENTIAL_VERSION="…"`
- [ ] 2.2 In `android.Dockerfile`, change `ENV BUNDLER_VERSION="…"` (line ~122) to `ARG BUNDLER_VERSION="…"`
- [ ] 2.3 Confirm both values are still referenced only on their immediately-following line (`grep -n BUILD_ESSENTIAL_VERSION android.Dockerfile script/`, same for `BUNDLER_VERSION`) — no `ENV`-scoped runtime consumer

## 3. Verify the manager now matches

- [ ] 3.1 Run a local Renovate dry-run (`npx renovate --platform=local`, `LOG_LEVEL=debug`) and grep the log for `android.Dockerfile` plus the extracted deb depNames
- [ ] 3.2 Confirm all nine apt pins (curl, git, lcov, ca-certificates, unzip, ruby-dev, build-essential, openjdk-17-jdk-headless, sudo) are extracted as `deb` dependencies — i.e. the manager matches nine pins, not zero
- [ ] 3.3 Build the Linux image and confirm via `docker inspect` that no `*_VERSION` apt pin appears in the image `Env` config (the `ENV → ARG` change took effect)

## 4. Wrap up

- [ ] 4.1 Open the change as a single small PR titled `fix(renovate): match android.Dockerfile for Debian package pins`
- [ ] 4.2 Note the CI dry-run guard (assert ≥1 deb dependency extracted) as a follow-up in the PR description, per design Non-Goals
