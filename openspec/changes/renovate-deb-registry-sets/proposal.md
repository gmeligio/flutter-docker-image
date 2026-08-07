## Why

The `openjdk-17-jdk-headless` pin in `android.Dockerfile` went stale for ten weeks and then broke `main`: the `android` stage failed with `E: Unable to correct problems, you have held broken packages` (run [31078705754](https://github.com/gmeligio/flutter-docker-image/actions/runs/31078705754)), fixed by hand in #529. Renovate never opened a PR for it, and never will under the current config.

The Mend job log for 2026-08-07 shows why. All nine apt pins resolved to a single registry URL:

```json
"deb": { "registryUrls": {
  "https://deb.debian.org/debian?suite=stable&components=main,contrib,non-free&binaryArch=amd64": { "stats": { "count": 9 } }
}}
```

Every pin — including the one annotated `suite=bookworm` — was looked up against `suite=stable`. The `registryUrlTemplate` branched on `{{#if release }}`, but the `matchStrings` regex captures a group named `suite`, never `release`, so the conditional always fell through to the hard-coded `suite=stable` else-branch. Since Debian 13 trixie became stable, the eight trixie pins kept working by coincidence while the lone bookworm pin resolved against a suite that does not ship `openjdk-17`:

```
"Failed to look up deb package openjdk-17-jdk-headless: no-result"
```

That line is logged at debug level. It never reached a PR, the Dependency Dashboard, or a warning — the pin simply stopped being maintained, silently, which is exactly the failure this capability exists to prevent.

Fixing the typo alone is not sufficient, and this is the load-bearing finding. A `registryUrlTemplate` renders to **one** URL, and the deb datasource accepts **one** suite per URL (only `components` is comma-split). But apt's candidate version is the maximum across *every* suite the image enables — `main`, `-updates` and `-security`. A one-URL mechanism therefore cannot express what correctness requires. Pointing the template at `bookworm` would still miss `bookworm-security`, where oldstable JDK security uploads (`~deb12uN`) land before they are folded into the main archive at a point release. Renovate would keep proposing a version older than the one apt installs — reproducing the exact JDK/JRE version skew that broke the build.

## What Changes

- **Remove `registryUrlTemplate` from the deb custom manager.** Suite selection moves to `packageRules`, whose `registryUrls` is a list, so a pin can be resolved against a *set* of suites. The deb datasource declares `registryStrategy: "merge"`, so releases from every listed suite are aggregated and Renovate's candidate becomes the one apt would install.
- **Add two deb `packageRules`**, each entry mirroring exactly one stanza of the image's real apt sources:
  - default → `trixie`, `trixie-updates`, `trixie-security` (`components=main`), matching `debian:13-slim`'s own sources;
  - override for `openjdk-17-jdk-headless` → `bookworm`, `bookworm-updates`, `bookworm-security` (`components=main,contrib,non-free,non-free-firmware`), matching `config/debian_12_bookworm.sources`.
- **Breaking: drop `suite=` from the `# renovate:` annotation.** `# renovate: suite=trixie depName=curl` becomes `# renovate: depName=curl`, and `matchStrings` no longer captures a `suite` group. Keeping a field that no longer steers anything would recreate the defect being fixed — a config that reads as though it works. The suite remains visible where it is actually decided: the `COPY config/debian_12_bookworm.sources` line in the stage that needs it, and the `~deb12uN` / `+deb13uN` marker in each pinned version string.

## Capabilities

### Modified Capabilities

- `linux-image-package-pinning`: the annotation grammar loses its `suite=` field, and the suite a pin resolves against becomes a set owned by `packageRules` rather than a single value derived from the annotation. Two existing requirements are restated; one requirement is added covering the set-of-suites invariant.

### New Capabilities

<!-- None. This change modifies how an existing capability is delivered; it introduces no new user-facing capability. -->

## Impact

- `.github/renovate.json` — deb custom manager loses `registryUrlTemplate` and the `suite` capture group; two deb `packageRules` added. Rule order is load-bearing: the `openjdk-17-jdk-headless` rule must stay after the default rule, because a later matching rule replaces `registryUrls` rather than extending it.
- `android.Dockerfile` — nine `# renovate:` annotations drop their `suite=` field. No `ARG` value, no installed package and no build behaviour changes; the image is byte-for-byte unaffected.
- Renovate now fetches 3 package indexes for trixie pins and 12 for the bookworm pin, versus 3 for everything before. Indexes are fetched once per run and shared across deps, and only `main` is large.
- No change to the `gx.toml` action manager, the `ARG`-not-`ENV` convention, `windows.Dockerfile` (no apt pins), or `config/version.json`.

## Non-Goals

- **A CI guard that fails when a pin resolves to nothing.** The deferred follow-up from `2026-06-08-fix-renovate-dockerfile-pins` (task 4.2, "assert ≥1 deb dependency extracted") would not have caught this: all nine dependencies *were* extracted, and one silently resolved to `no-result` afterwards. The guard that would have caught it asserts every deb pin yields a lookup result, which needs a network dry-run against `deb.debian.org`. That is worth doing and is now better motivated, but it is a separate change with its own CI cost.
- **Replacing openjdk-17 with trixie's openjdk-21.** This would delete `config/debian_12_bookworm.sources`, the cross-suite pin and this entire class of bug, and drop an oldstable JDK's CVE surface from the image. It also changes the JDK the published image offers, so it is a product decision affecting downstream Flutter/AGP builds — raised for the maintainer, deliberately out of scope here.
