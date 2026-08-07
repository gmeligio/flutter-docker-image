## 1. Move suite selection into packageRules

- [x] 1.1 Add a default deb `packageRules` entry (`matchDatasources: ["deb"]`) with `registryUrls` for `trixie`, `trixie-updates` and `trixie-security`, `components=main` — mirroring `debian:13-slim`'s own sources
- [x] 1.2 Add an override entry (`matchPackageNames: ["openjdk-17-jdk-headless"]`) with `registryUrls` for `bookworm`, `bookworm-updates` and `bookworm-security`, `components=main,contrib,non-free,non-free-firmware` — mirroring `config/debian_12_bookworm.sources`
- [x] 1.3 Place the override after the default entry, and record the ordering constraint in its `description` (a later matching rule replaces `registryUrls`)
- [x] 1.4 Confirm component lists against the failing build's `apt-get update` output: trixie publishes `main` only; bookworm publishes all four components

## 2. Remove the mechanism that could not be correct

- [x] 2.1 Delete `registryUrlTemplate` from the deb custom manager — it renders one URL and the deb datasource takes one suite per URL, so it cannot address a suite set
- [x] 2.2 Drop the `(?<suite>…)` capture group from `matchStrings`, leaving `depName` and `currentValue`
- [x] 2.3 Add a `description` to the manager stating that suite selection lives in `packageRules`, so the next reader does not re-add a template

## 3. Simplify the annotation grammar (breaking)

- [x] 3.1 Rewrite all nine `# renovate: suite=… depName=…` annotations in `android.Dockerfile` to `# renovate: depName=…`
- [x] 3.2 Confirm no `ARG` value, installed package, or build behaviour changed — the diff touches comment lines only
- [x] 3.3 Confirm `windows.Dockerfile` carries no `# renovate:` apt pins and needs no edit

## 4. Verify

- [x] 4.1 Re-run the `matchStrings` regex against both Dockerfiles and confirm all nine pins still extract with correct `depName`/`currentValue` — 9/9
- [x] 4.2 Run `script/renovate_validate.sh` — `INFO: Config validated successfully`
- [x] 4.3 Run `LOG_LEVEL=debug npx renovate --platform=local --dry-run=lookup` and confirm the constructed component URLs are exactly the intended set: 3 trixie (`main`) and 12 bookworm (4 components × 3 suites), with both families present so both rules demonstrably fired
- [x] 4.4 Confirm no URL outside that set is constructed — in particular no `dists/stable/…`, the suite every pin previously resolved against
- [ ] 4.5 After merge, check the next Renovate job log: the `getReleases` summary lists more than one deb `registryUrl`, and no `Failed to look up deb package openjdk-17-jdk-headless: no-result` warning appears — **cannot be done pre-merge; egress to `deb.debian.org` is blocked in the sandbox, so lookups cannot succeed locally and only URL construction is verifiable**

## 5. Wrap up

- [x] 5.1 Open as a draft PR describing the root cause, the structural argument for removing `registryUrlTemplate`, and the breaking annotation change
- [x] 5.2 Record two follow-ups in the PR description: the CI guard asserting every deb pin resolves (the `2026-06-08` deferral, re-motivated — extraction succeeded here and resolution failed afterwards), and the openjdk-17 → trixie openjdk-21 migration that would delete this special case entirely
