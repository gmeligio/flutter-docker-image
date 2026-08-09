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

## 4. Establish what catches a stale suite set

- [x] 4.1 Enumerate the failure modes: (a) base image moves to a new Debian release while `registryUrls` name the old suites; (b) `registryUrls` name a suite that never resolves while the pinned versions still install
- [x] 4.2 Determine whether (a) is silent — it is not: apt pins are exact-version matches, so `apt-get install` fails hard on the new release and `build.yml` builds both targets on every PR
- [x] 4.3 Confirm against precedent — `4cddcea` (Debian 12→13 major) merged with a human co-author and rewrote every pin, the annotations, `renovate.json` and added `config/debian_12_bookworm.sources` in one PR
- [x] 4.4 Confirm (b) is the genuinely silent one, and that mirroring sources files does not catch it — the bookworm half *was* mirrored by `config/debian_12_bookworm.sources` for the entire ten weeks the bug ran
- [x] 4.5 Drop `config/debian_13_trixie.sources`: inert documentation, nothing reads it, a second copy to keep in sync, and no signal beyond what `android.Dockerfile:1` already gives. Record the co-update instruction in the trixie rule's `description` instead

## 5. Make the Renovate config locally checkable

- [x] 5.1 Add `[tasks.lint]` to `mise.toml` running the previously orphaned `script/renovate_validate.sh`
- [x] 5.2 Fix the script's mode bit (644 → 755, staged via `git update-index --chmod=+x`); every script CI runs is 755, and this one could not be executed
- [x] 5.3 Keep it out of CI and record why in the task comment: Renovate config changes ship on a `renovate/reconfigure` branch where the Renovate app validates the config and reports back, so a workflow would duplicate it

## 6. Verify

- [x] 6.1 Re-run the `matchStrings` regex against both Dockerfiles and confirm all nine pins still extract with correct `depName`/`currentValue` — 9/9
- [x] 6.2 Run `mise run lint` — `INFO: Config validated successfully`
- [x] 6.3 Run `LOG_LEVEL=debug npx renovate --platform=local --dry-run=lookup` and confirm the constructed component URLs are exactly the intended set: 3 trixie (`main`) and 12 bookworm (4 components × 3 suites), with both families present so both rules demonstrably fired
- [x] 6.4 Confirm no URL outside that set is constructed — in particular no `dists/stable/…`, the suite every pin previously resolved against
- [x] 6.5 Run `gx lint` — no issues (workflows unchanged in the end; the lint job was reverted after the maintainer noted `renovate/reconfigure` already covers validation)
- [x] 6.6 Deferred out of this change — see "Deferred verification" below. Every locally-verifiable property is checked above; the remaining one needs network egress this environment does not have

## 7. Wrap up

- [x] 7.1 Open as a draft PR describing the root cause, the structural argument for removing `registryUrlTemplate`, and the breaking annotation change
- [x] 7.2 Record two follow-ups in the PR description: the CI guard asserting every deb pin resolves (the `2026-06-08` deferral, re-motivated — extraction succeeded here and resolution failed afterwards), and the openjdk-17 → trixie openjdk-21 migration that would delete this special case entirely

## Deferred verification

**Not done, and not doable in this change.** This change is archived with its central behaviour — that a pin now *resolves* — unobserved. What was verified is URL construction, not resolution: `deb.debian.org` egress is blocked in the sandbox, so no lookup can succeed locally.

The observation is a single log read, on the first Renovate run after PR #531 merges:

- the `getReleases` summary lists more than one deb `registryUrl` (before the fix it listed exactly one, `suite=stable`, for all nine pins);
- no `Failed to look up deb package openjdk-17-jdk-headless: no-result` appears;
- upgrade PRs appear for pins gone stale since 2026-06-10. Expect a **burst** — `group:allNonMajor` will likely batch them into one PR, and `automerge: true` means they merge on green. That is success, not noise.

If the log is not clean, it names what is still wrong, which is better input for a guardrail than anything specifiable today. Context for why this matters: the deb manager matched no file for 15 months (`Dockerfile` → `android.Dockerfile` rename, fixed by #488 on 2026-06-10), then resolved against the wrong suite until this change. Renovate has never once run with both defects fixed, so there is no track record behind the config.
