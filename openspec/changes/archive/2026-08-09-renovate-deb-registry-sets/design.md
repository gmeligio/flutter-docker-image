## Context

`android.Dockerfile` pins nine apt packages to exact versions. Renovate keeps them current via a `deb`-datasource custom manager. Two facts about the environment drive every decision below.

**apt resolves against a set of suites.** The android stage runs with six repositories enabled — trixie, trixie-updates, trixie-security from the base image, plus bookworm, bookworm-updates, bookworm-security from `config/debian_12_bookworm.sources`. apt's candidate for a package is the highest version across all of them. Ground truth from the failing build's `apt-get update` output:

```
Get:7  .../debian trixie/main amd64 Packages
Get:8  .../debian trixie-updates/main amd64 Packages
Get:9  .../debian-security trixie-security/main amd64 Packages
Get:10 .../debian bookworm/contrib amd64 Packages
Get:11 .../debian bookworm/non-free amd64 Packages
Get:12 .../debian bookworm/main amd64 Packages
Get:13 .../debian bookworm/non-free-firmware amd64 Packages
Get:14 .../debian bookworm-updates/main amd64 Packages
Get:15 .../debian-security bookworm-security/contrib amd64 Packages
Get:16 .../debian-security bookworm-security/non-free-firmware amd64 Packages
Get:17 .../debian-security bookworm-security/main amd64 Packages
```

Note the asymmetry the components lists must respect: trixie carries `main` only, bookworm carries all four components.

**A Renovate registry URL addresses one suite.** In `lib/modules/datasource/deb/url.ts`, `constructComponentUrls` splits `components` on commas but uses `suite` verbatim; `-security` additionally lives under a different path (`/debian-security`, not `/debian`). So one URL = one suite, and no amount of template cleverness changes that.

## Goals / Non-Goals

**Goals**

- Renovate's candidate for a pin equals the version apt would install.
- One mechanism decides suites, in one place, with no silently-inert config.
- Divergence between the config and the image's apt sources is visible by reading them side by side.

**Non-Goals**

- A CI guard for unresolvable pins (see proposal Non-Goals — real, but separable).
- Migrating off openjdk-17 (product decision).
- Any change to what the built image contains.

## Decisions

### Suite selection moves from `registryUrlTemplate` to `packageRules`

`registryUrlTemplate` renders a single string. Correctness requires three URLs per suite family. The mechanism is structurally incapable of the job, so it is removed rather than repaired — repairing the `{{#if release }}` typo would fix the *symptom* (wrong suite) while leaving the *defect* (only one suite reachable).

`packageRules.registryUrls` is a list, and the deb datasource sets `registryStrategy = 'merge'`, which aggregates releases across every listed registry. That is exactly apt's "max across enabled suites" semantics.

**Alternatives rejected**

- *Fix the template to `suite={{suite}}`.* Verified to work — Renovate spreads all named capture groups into the template context (`createDependency` calls `template.compile(tmpl, {...groups, …}, false)`, with field filtering disabled) — but it still reaches only `bookworm`, never `bookworm-security`. It would leave the JDK pin lagging apt and the build fragile in the same way.
- *Keep the template and add packageRules on top.* `packageRules.registryUrls` replaces the extracted value, so the template would be dead config for every pin a rule covers. Two mechanisms where one is inert is precisely the "looks correct, isn't" trap this change exists to remove.
- *Comma-separated suites in one URL.* Not supported; `suite` is used verbatim. And `-security` is a different base path regardless.
- *`suite=stable` / `suite=oldstable` aliases.* These track whatever Debian currently calls stable, so they move under the repo without a commit — the mechanism that produced this bug when trixie replaced bookworm as stable. Codenames are pinned deliberately: when the base image moves to Debian 14, updating these URLs is a conscious edit rather than a silent retarget.

### Rule order is the override mechanism

Renovate applies `packageRules` in array order and a later matching rule's config overrides earlier config, replacing `registryUrls` wholesale. So the default (trixie) rule comes first and the `openjdk-17-jdk-headless` rule second. This is load-bearing and is stated in the rule's own `description` so a reader reordering the array sees the constraint at the point of edit.

### The `suite=` annotation field is removed, not retained as documentation

Once `packageRules` owns suite selection, `suite=` in the Dockerfile steers nothing. Leaving it would be strictly worse than deleting it: a reader would reasonably believe editing it changes behaviour, which is the same false affordance that hid this bug for ten weeks. Deleting it makes `.github/renovate.json` the single source of truth for *where to look* and the annotation the single source of truth for *what to look for*.

Locality is not lost. A maintainer asking which suite a pin resolves against has two signals already in the Dockerfile: the `COPY config/debian_12_bookworm.sources` line in the stage that adds bookworm, and the version string itself (`17.0.20+8-1~deb12u1` versus `8.14.1-2+deb13u4`).

### Each `registryUrls` entry mirrors exactly one apt sources stanza

Suite *and* component list are copied from the sources the image actually enables, rather than using one convenient superset for both families. A superset would make Renovate fetch indexes apt never sees; missing components would hide packages apt can install. Both failures are silent — the deb datasource logs a failed component fetch at debug and continues. Mirroring keeps the invariant checkable by eye: every URL corresponds to one `Types/URIs/Suites/Components` stanza in either `debian:13-slim`'s sources or `config/debian_12_bookworm.sources`.

### The base image's suites are not mirrored into a second file

A checked-in `config/debian_13_trixie.sources`, recording the suites `debian:13-slim` already ships, was written and then deleted. Recording it does not make the invariant *checked* — nothing would read the file. It would be inert documentation whose agreement with `renovate.json` is maintained only by a maintainer noticing, and it adds a second copy to keep in sync while offering no signal the `FROM` line does not already offer. `android.Dockerfile:1` is the authoritative statement of which Debian release is in play; a reviewer comparing `registryUrls` against that line has the same information. The trixie rule's `description` now carries the co-update instruction instead, which costs nothing and sits where the URLs are edited.

The real question it was meant to answer — *what catches a stale suite set?* — is answered below on its merits.

### What a Debian release bump actually does, and what catches it

Renovate's docker manager bumps `FROM debian:*-slim` unattended, and `automerge: true` is global. Precedent exists for both scales: `8476e0c` (13.4→13.6), `d301c28`, `3ca7c22` are minors, and `4cddcea` was a **major**, 12→13.

That major bump is the useful evidence, because it is the exact scenario in question and it is in the history. It did not merge silently. `4cddcea` carries a human co-author alongside `renovate[bot]`, and in the same PR the pins were rewritten (`7.88.1-10+deb12u14` → `8.14.1-2`), the annotations retargeted `release=bullseye` → `suite=trixie`, `config/debian_12_bookworm.sources` was created, and `renovate.json` was edited. A Debian major bump is not a quiet one-line change: **it breaks the build loudly and immediately**, because every apt pin is an exact-version match (`curl="$CURL_VERSION"`) against an archive that no longer carries those versions, and `apt-get install` fails hard. `build.yml` builds both image targets on every pull request, so this surfaces as a red PR before merge.

So the feared "silent rot" splits into two failure modes with different answers:

| Failure mode | Silent? | Caught by |
|---|---|---|
| Base image moves to a new Debian release; `registryUrls` still name the old suites | **No** | The PR build fails — pinned versions are absent from the new release, `apt-get install` errors, and the pins must be rewritten by hand in that same PR (as in `4cddcea`) |
| `registryUrls` name a suite that never resolves, while the pinned versions still install | **Yes** | Nothing today. Renovate logs `no-result` at debug level; the build stays green because the pinned versions remain in the archive. This is precisely the ten-week `openjdk-17-jdk-headless` bug |

Only the second is genuinely undetectable, and a mirrored sources file would not have caught it either — the bookworm half *was* mirrored by `config/debian_12_bookworm.sources` throughout, and the bug still ran for ten weeks. What catches it is a lookup-result assertion, which needs network egress to `deb.debian.org`; that remains the deferred follow-up in Non-Goals, now with a sharper justification.

**Alternative rejected:** *generate the `registryUrls` from a manifest.* The repo has manifest→codegen→git-diff-gate machinery (`config/version.json`, `config/schema.cue`, `mise run docs`, the `validate-generated-config` job). It does not fit here. `config/schema.cue` models no OS concept at all, and `FROM debian:13.6-slim` is bumped by Renovate's docker manager entirely outside the `version.json` update path — so generating six URLs would mean inventing a `debian` manifest dimension *and* rewiring `update-version.yml` to own the base-image bump. It would also break a repo convention: everything under `.github/` is hand-written (`gx.toml` is hand-maintained, `gx.lock` is its generated artifact; `docs/contributing.md:89` instructs humans to edit `.github/renovate.json`), while generated output lands at repo root, `examples/`, and `test/`. Order-of-magnitude cost, and it would not catch the one failure mode that is actually silent.

### Renovate config validation stays local

`script/renovate_validate.sh` existed before this change, referenced by nothing — no workflow, no task, no doc — and carrying mode 644 while every script CI runs is 755. It was unrunnable dead code. `mise run lint` makes it reachable and the mode bit is fixed.

It is **not** promoted to a CI job. Renovate config changes ship on a `renovate/reconfigure` branch, where the Renovate app validates the config itself and reports failures back on the PR. A workflow running `renovate-config-validator` would re-run the authoritative check and add a job without adding a signal. The local task is the faster loop for the maintainer, not a second gate.

Either way the check is syntax-only — it does not evaluate enum values and cannot tell whether a pin resolves against the right suite. It would not have caught the bug this change fixes, and is not claimed to.

## Risks / Trade-offs

- **More index fetches.** The bookworm pin now costs 12 component fetches instead of 3. Indexes are fetched once per run and shared across dependencies (the prior job log shows 8 of 9 lookups served from cache), and only `main` is large — bookworm-updates was 6.9 kB, bookworm-security 325 kB in the build log. Acceptable for correctness.
- **Base-image upgrades need a config edit.** Moving to Debian 14 requires updating three URLs. This is deliberate (see the alias alternative above), and the failure mode is loud — not by assertion but by mechanism: the exact-version apt pins stop installing on the new release, so `apt-get install` fails and the PR build goes red before merge. `4cddcea` (the 12→13 major bump) is the worked precedent — it rewrote every pin, the annotations, and `renovate.json` in one human-reviewed PR. Contrast `suite=stable`, which retargeted silently and kept building.
- **The silent `no-result` remains silent.** This change removes the *cause*, not the *class*. A future misconfiguration could still produce an unresolvable pin that only debug logs mention. That is what the deferred CI guard is for.

## Verification

Network egress to `deb.debian.org` is blocked in the development sandbox, so lookups cannot succeed locally; a local dry-run verifies **URL construction**, and the next Renovate run verifies **resolution**.

`LOG_LEVEL=debug npx renovate --platform=local --dry-run=lookup` constructs exactly the intended set and nothing else:

```
.../debian/dists/trixie/main/binary-amd64
.../debian/dists/trixie-updates/main/binary-amd64
.../debian-security/dists/trixie-security/main/binary-amd64
.../debian/dists/bookworm/{main,contrib,non-free,non-free-firmware}/binary-amd64
.../debian/dists/bookworm-updates/{main,contrib,non-free,non-free-firmware}/binary-amd64
.../debian-security/dists/bookworm-security/{main,contrib,non-free,non-free-firmware}/binary-amd64
```

Both families appear, and no rule other than the `openjdk-17-jdk-headless` override references bookworm — so the override fired and the default covered the rest. All nine pins still extract, and `script/renovate_validate.sh` reports `Config validated successfully`.

The acceptance test on the next Renovate run: the job log's `getReleases` summary lists more than one deb `registryUrl`, and no `Failed to look up deb package … : no-result` warning appears for `openjdk-17-jdk-headless`.
