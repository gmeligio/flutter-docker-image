# Research: Renovate improvements as a whole (#532)

Scope note: the Java version wiring and number are handled in a separate PR. Java 17 is assumed
throughout; plan item 3 of #532 ("Derive the Java version from Flutter") is out of scope here and
is only referenced where it interacts with pin provenance.

Evidence base: the Mend job log for 2026-08-07
(`019fdc2a-e895-710a-91be-a9580b10aaaf`, 173 JSON-lines records), the repository at `0bc825f`,
PR #531's branch, and the Renovate source at `ecadb0c` (2026-08-08).

---

## Context

Nine apt packages are pinned in `android.Dockerfile`. Renovate is supposed to keep them current
via a `deb`-datasource custom manager. It has never once bumped the one that broke.

```
  DECLARED                    RESOLVED                    INSTALLED
  (what a human reads)        (what Renovate queries)     (what apt does)

  android.Dockerfile:7-145    .github/renovate.json:42    debian:13.6-slim sources
  ┌──────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
  │ # renovate:          │    │ registryUrlTemplate  │    │ trixie               │
  │   suite=trixie   ×8  │───▶│  {{#if release}}     │    │ trixie-updates       │
  │   suite=bookworm ×1  │ ╳  │    release={{release}}│   │ trixie-security      │
  │                      │    │  {{else}}            │    ├──────────────────────┤
  │ ARG *_VERSION="..."  │    │    suite=stable  ◀───┼────│ + config/debian_12_  │
  └──────────────────────┘    │  {{/if}}             │    │   bookworm.sources   │
           │                  └──────────────────────┘    │   bookworm           │
           │                             │                │   bookworm-updates   │
           │                             │                │   bookworm-security  │
           ▼                             ▼                └──────────────────────┘
    suite= is captured             all 9 pins query                  │
    as (?<suite>...)               ONE url: suite=stable             ▼
    at renovate.json:40                                       apt candidate =
           │                                                  max across ALL
           └────────── never referenced ──────────╳           enabled suites
                       (template branches on
                        `release`, never bound)
```

`{{#if release }}` branches on a variable no `matchStrings` group ever binds, so the conditional
always falls through to the hard-coded `suite=stable` else-branch. The job log confirms all nine
pins resolving to a single registry URL (`Lookup statistics`, log line 170; the `deb` datasource
shows `count: 9`).

Since Debian 13 trixie became stable, the eight `suite=trixie` pins kept working **by coincidence**.
The lone `suite=bookworm` pin resolved against a suite that does not ship openjdk-17:

```
line 89, level 20:  "Failed to look up deb package openjdk-17-jdk-headless: no-result"
```

Git history is the proof that this is not theoretical. `renovate[bot]` has bumped
`android.Dockerfile` many times — `e726b7f` (#512) moved the trixie pins as part of "update all
non-major dependencies", and a long tail of commits bumped the `debian` base tag and digest. The
openjdk pin appears exactly once, in `424f731` (#529), authored by a human. **The automation that
owns that pin has never successfully bumped it.**

---

## Findings

### F1 — The issue's central claim about the alarm is wrong (corrected here)

#532 states, after its 2026-08-08 update, that `no-result` is *not* debug-only, that Renovate
called `logger.warn(…, 'Package lookup failures')`, and that "the alarm existed and was unmuted"
— only its *delivery* was discarded by silent mode.

**Verified against both the log and the Renovate source: this is incorrect.**

Log evidence — level counts across all 173 records:

```
level 30 (INFO):   6 records
level 20 (DEBUG): 168 records
level 40+ (WARN):  0 records          ◀── none
```

There is no `Package lookup failures` record anywhere in the log. Line 89 is level 20.

Source evidence explains why. The `res.warnings.push(warning)` the issue cites is real
([`lookup/index.ts#L288-L303`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/workers/repository/process/lookup/index.ts#L288-L303)),
and it is emitted at **`logger.debug`**, matching the observed record's `{dependency, packageFile}`
binding exactly. `logger.warn(…, 'Package lookup failures')` is also real
([`errors-warnings.ts#L60`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/workers/repository/errors-warnings.ts#L60))
— but it lives in the **private** `getDepWarnings()`, called only by three exported wrappers, all
of which are *rendering* paths (PR body, dashboard, onboarding PR).

**The WARN is a side effect of rendering, not of detection. No render, no warn.**

And `mode=silent` cuts every render path off upstream of the warn:

```
  detection                                    delivery
  ┌───────────────────────────────┐            ┌──────────────────────────────┐
  │ lookup/index.ts:288           │            │ dependency-dashboard.ts      │
  │   logger.debug(...)  ◀── the  │            │   L343: if mode==='silent'   │
  │   res.warnings.push()   only  │──────┐     │          return   ───────╳   │
  └───────────────────────────────┘  log │     │   L563: getDepWarnings...    │
                                    we got│    │          ▲ never reached     │
                                          │    └──────────────────────────────┘
                                          │    ┌──────────────────────────────┐
                                          └───▶│ branch/index.ts:226          │
                                               │   no branch ⇒ no PR body     │
                                               │   ⇒ getDepWarningsPR ───╳    │
                                               └──────────────────────────────┘
```

`ensureDependencyDashboard` returns at
[L343-L348](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/workers/repository/dependency-dashboard.ts#L343-L348),
**220 lines before** `getDepWarningsDashboard` is called at L563. This is visible in the log as the
adjacent pair at lines 151/152: `ensureDependencyDashboard()` immediately followed by
`Dependency Dashboard issue is not created, updated or closed when mode=silent`.

**Why this correction matters for the plan.** #532's plan item 2 is framed as "restore the alarm" —
as though setting `mode: full` re-enables an existing warning. It does not restore anything; it
*constructs* the alarm for the first time, and only as a by-product of a rendering path. The
original issue text (now in the collapsed section) was closer to right than its own correction:
the failure is silent by construction, not muted in transit. Consequence: **`mode: full` alone is
not an observability control.** A future lookup failure would surface only if Renovate happens to
render a dashboard — which is real coverage, but it is incidental coverage, and it is coverage
this repo cannot test locally or gate in CI.

### F2 — `mode=silent` comes from global env config, not per-repository portal settings

#532 states: *"`mode` is set outside the repository — it is absent from `.github/renovate.json`
and from the log's `File`/`CLI`/`Env` config objects, so it comes from Mend's per-repository
settings."*

**The log says otherwise.** `mode` is present in the `Env config` record:

```
line  7  File config     mode present: False
line  9  CLI config      mode present: False
line 10  Env config      mode present: True   ◀── mode = "silent"
line 12  Combined config mode present: True
```

`Env config` is Mend's injected `RENOVATE_CONFIG` (the same object carries `platform`, `token`,
`repositories`, `globalExtends`, `hostRules`, `binarySource`). This is **global/admin config**, and
the distinction is load-bearing for whether the repo can override it.

### F3 — `"mode": "full"` in `.github/renovate.json` will win. High confidence.

Three independent lines of evidence:

1. **Merge semantics.** `mergeChildConfig(parent, child)` is a plain spread — child overrides
   parent
   ([`utils.ts#L7-L57`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/config/utils.ts#L7-L57)).
   Global env config is merged first
   ([`parse/index.ts#L58`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/workers/global/config/parse/index.ts#L58)),
   then repo config is merged **on top** as the child
   ([`merge.ts#L325`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/workers/repository/init/merge.ts#L325)).
   Global is a default, not a floor.
2. **`mode` is not `globalOnly`.** Its full definition
   ([`options/index.ts#L10-L16`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/config/options/index.ts#L10-L16))
   is five keys: `name`, `description`, `type: 'string'`, `default: 'full'`,
   `allowedValues: ['full','silent']`. No `globalOnly`, no `stage`. So
   `renovate-config-validator` accepts it in a repo config.
3. **Maintainer guidance.** For this exact Mend "Scan Only" situation, Renovate maintainer
   RahulGautamSingh: *"Pick the `silent` option and create a `renovate.json` with this present
   `mode: 'full'` in repos you want to go `full`."*
   ([discussion #39198](https://github.com/renovatebot/renovate/discussions/39198), selected answer).
   The design intent is stated in [#26724](https://github.com/renovatebot/renovate/issues/26724).

Two escape hatches could defeat this, and **both are ruled out for this log**:

- `force` — anything under `config.force` is re-applied after every merge
  ([`utils.ts#L56`](https://github.com/renovatebot/renovate/blob/ecadb0c88ec4aa4c163499b48d19b6a9cc7c2b1a/lib/config/utils.ts#L56)),
  making it genuinely non-overridable. `grep '"force":{'` over the log: **no matches**.
- `dryRun` — takes precedence over `mode`; Mend's own docs describe silent mode as
  `dryRun=lookup`. `grep '"dryRun":'` over the log: **no matches**.

So `mode` is a plain overridable key here. Residual risk is Mend changing server-side behavior,
which the next job log detects cheaply (absence of the `Repository is running with mode=silent`
line).

### F4 — The blast radius of silent mode is wider than the missed alarm

The same run computed and then withheld two genuine updates:

```
line 140:  Branch renovate/debian-13.6-slim creation is disabled because mode=silent
line 149:  Branch renovate/mcr.microsoft.com-windows-servercore-ltsc2025 creation is
           disabled because mode=silent
```

Note `renovate/debian-13.6-slim`: the base image is already at `13.6-slim`
(`android.Dockerfile:1`), so this is a digest bump being withheld. Combined with
`"automerge": true` (`.github/renovate.json:10`), the current configuration composes into
*"changes merge without producing a dashboard or PR trail"* — a property no reviewer of either
setting alone would predict.

### F5 — The suite fact is triplicated, and the correct answer is already in the repo

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  "which suite does openjdk-17-jdk-headless come from?"             │
  ├────────────────────────────────────────────────────────────────────┤
  │  android.Dockerfile:143         "bookworm"      ✓ correct, INERT   │
  │  .github/renovate.json:42       "stable"        ✗ WRONG, AUTHORITY │
  │  config/debian_12_bookworm      "bookworm"      ✓ correct, BUILD   │
  │    .sources:5,11                                                    │
  └────────────────────────────────────────────────────────────────────┘
```

The data needed to fix this is already present, per-pin, at the right granularity. It is dropped
in transit by one line of Handlebars. Grep for `bookworm`, `trixie`, or `debian` across `test/`,
`.github/`, `script/`, and `docs/`: **zero matches**. The suite concept is entirely absent from the
verification layer.

### F6 — The base image's suite is not derivable from anything

`android.Dockerfile:1` pins `debian:13.6-slim@sha256:020c0d…`. Nothing in the repo maps 13 → trixie.
Renovate's **built-in docker manager** bumps this tag (`8476e0c`, `d301c28`, `4cddcea`) and is not
mentioned in `.github/renovate.json` at all — it runs on `config:recommended` defaults.

So the base image and the packages installed onto it are updated by two managers that share no
configuration and no consistency check. A `debian:14` bump would arrive as a clean, automergeable
Renovate PR and silently invalidate eight `suite=trixie` annotations. `suite=stable` would follow
it; the pins would not. **This is the identical mechanism that produced #532 when trixie replaced
bookworm as stable** — it is not a hypothetical, it is the same bug scheduled to recur.

### F7 — No check in the repo knows anything about pins or suites

`build.yml` runs on `pull_request:` with no `paths:` filter, so Renovate PRs get the same jobs a
human PR gets. Renovate is *inside* the choke point. The problem is what the choke point knows:

| check | runs on `renovate/*`? | sees apt pins? |
|---|---|---|
| `build-image` (`build.yml:41`) | yes | **incidentally** — a bogus version fails `apt-get install` |
| `validate-version-files` (`build.yml:390`) | yes | no — pins aren't in `config/version.json` |
| `validate-generated-config` (`build.yml:407`) | yes | no |
| `build-docs` (`build.yml:432`) | yes | no |
| `gx.yml` | **no** — `paths:` excludes `renovate.json` | no |
| `ci.yml` | **no** — `on: push: branches: [main]` only | post-merge only |

`ci.yml` is the workflow that went red for #532 — the failure surface for a bad pin is **after
merge, on main**. And `.github/renovate.json` itself bypasses the choke point entirely: no workflow
reads it, no job validates it, and `gx.yml:4-9`'s `paths:` filter — the obvious home — omits it.

`script/renovate_validate.sh` exists (one line: `npx --yes --package renovate --
renovate-config-validator --strict`). Grep for its call sites across `.github/`, `mise.toml`, and
`script/`: **zero**. Its only references are checkboxes in an *archived* change
(`openspec/changes/archive/2026-06-08-fix-renovate-dockerfile-pins/tasks.md:4`, `design.md:48`).
It is a checkbox, not a check. It also could not be adopted as written: `npx --yes --package
renovate` is an unpinned tool install, and `ci-runtime-tool-versioning/spec.md:9` requires CI
runtime tools be pinned in `mise.toml`, which has no `renovate` entry.

### F8 — The gap was correctly identified ten weeks ago and had nowhere to be deferred to

`openspec/changes/archive/2026-06-08-fix-renovate-dockerfile-pins/design.md:53-55`:

> "The failure this change fixes was silent — that is the core lesson… A regression would again be
> silent under today's tooling — which is precisely why the follow-up CI dry-run guard… is called
> out as the real recurrence defense."

It was listed as a Non-Goal (`design.md:17`), never filed as a change, and #532 is its recurrence.
**Deferral without a backlog artifact is deletion.**

The same design doc also predicted #532's exact scenario and mis-classified it (`design.md:43`):

> "**[Renovate may propose `currentValue` mismatches if a pinned version is not in the configured
> suite]** → Pre-existing behavior of the deb datasource, unchanged by this fix; surfaces as a
> normal Renovate PR, not a silent failure."

The last clause is backwards — it surfaces as *no PR at all*. The author had no model object for
"suite", so they reasoned about it as a datasource quirk rather than a fact under their control.

### F9 — The repo already has the right pattern, twice, and the apt pins are excluded from both

**Pattern A — data + contract + enforcement.** `config/version.json` is data, `config/schema.cue` is
the contract, `cue vet` is enforcement, running at seven call sites (`build.yml:390,501`;
`update-version.yml:100,204,308,393`). `config/android.cue` + `script/update_test.sh` extend it to
*derive* `test/android.yml`, and `build.yml:407-414` asserts the derived output is committed via
`git diff --exit-code`.

**Pattern B — manifest + propagation + lint (the gx loop).** Renovate edits one manifest, gx
propagates and enforces, `gx lint` is a required check.

| | actions (gx) | apt pins |
|---|---|---|
| manifest | `.github/gx.toml` | none — `ARG`s found by regex |
| lock / resolved state | `.github/gx.lock` | none |
| propagation | `gx tidy` (`gx.yml:76`) | none |
| enforcement | `gx lint` (`gx.yml:39`) | none |
| spec | `actions-version-tracking` | `linux-image-package-pinning` (describes, doesn't enforce) |

The gx boundary is the repo's own answer to *"Renovate edits a manifest, local tooling validates
the consequence."* The deb pins were never given a manifest to edit, so there is nothing to
validate. Note also that `renovate.json:19,28,30` hardcodes gx's file path and TOML grammar, and
`gx.yml`'s `paths:` filter doesn't cover `renovate.json` — a gx schema change breaks Renovate's
custom manager silently in either direction.

### F10 — Renovate is the only external-service config in this repo whose failure is silent

| artifact | consumer | failure mode |
|---|---|---|
| `.github/renovate.json` | Mend SaaS | **silent — absence of PRs** |
| Docker Scout config | Docker Hub | loud — job fails |
| `.github/workflows/scorecard.yml` | OSSF | loud — job fails |
| branch ruleset | GitHub settings | loud — push blocked |

The repo already has a convention for out-of-band config: **write the contract as a spec
requirement with the failure mode as a scenario.** `ci-repo-governance/spec.md:53-64` does exactly
this for ruleset `bypass_actors`, explicitly acknowledging the setting lives elsewhere.
`ci-workflow-readability/spec.md:50-55` does it for required-check names.

Applied inventory:

| out-of-band setting | recorded in-repo? |
|---|---|
| ruleset `bypass_actors` | yes — `ci-repo-governance/spec.md:53-64` |
| required-check names | yes — `ci-workflow-readability/spec.md:50-55` |
| `required_approving_review_count = 0` | yes — `ci-repo-governance/spec.md:75` |
| `DOCKER_HUB_*` secrets | yes — `ci-image-vulnerability-scan/spec.md:106-115` |
| `VERIFIED_COMMIT_CLIENT_ID` | partial — used at `gx.yml:58-59`; no spec requirement |
| **Mend `mode`** | **no — nowhere** |

`mode` is the one behavior-critical setting with no in-repo representation, and it is the setting
that determines whether every other Renovate guarantee is observable at all.
`linux-image-package-pinning/spec.md:32` asserts *"THEN Renovate opens an upgrade PR for that pin
on its weekly schedule"* — a requirement whose truth was controlled entirely by a value no commit
could see.

### F11 — Capability boundaries fight this work

Renovate as a concern is scattered across four capabilities:

- `linux-image-package-pinning/spec.md:9-32` — owns the file pattern, the `ARG` convention,
  `depName` correctness. **Does not own the suite.** "suite" appears only inside quoted annotation
  syntax (`:20`, `:62`); no requirement constrains *which* suite or that the annotation's suite
  reaches the request. #532 fits inside this capability's Purpose (`:5`, "rather than silently
  going stale") and outside all three of its Requirements.
- `actions-version-tracking` — Renovate-for-actions. Complete and enforced. Purpose still reads
  *"TBD - created by archiving change adopt-gx-for-actions"* (`spec.md:4`).
- `ci-repo-governance/spec.md:73-98` — automerge and required checks.
- `ci-runtime-tool-versioning/spec.md:9` — would own a pinned `renovate` CLI.

Nothing owns `.github/renovate.json` as an artifact. Nothing owns "the Debian suite the image
builds against". The base image tag at `android.Dockerfile:1` is owned by no spec at all.

### F12 — Incidental defects found (file separately, not in scope)

- `docs/contributing.md:89-91` instructs contributors to add actions to *"the automerge array"* in
  `renovate.json`. No such array exists — `.github/renovate.json:10` is a global boolean. Stale
  documentation of a replaced config.
- `script/latest_android_sdk_command_line_tools.sh:6` is
  `version=$($command_line_tools_url | grep -o '[0-9]\+')` — it executes a URL as a command and
  assigns to an unused variable. It, `script/latest_android_ndk.sh`, and
  `script/latest_android_sdk_platforms.sh` are referenced by no workflow. They make several
  `config/version.json` fields *look* automated when they are hand-maintained.
- `config/version.json`'s `android.cmake.version` has no producer at all.

---

## Where PR #531 lands

#531 is well-constructed and its diagnosis is correct. It removes `registryUrlTemplate` entirely
(rather than repairing `{{#if release}}` → `{{suite}}`) on the grounds that a template renders one
URL while apt's candidate is the max across a *set* of suites — so it moves suite selection into
`packageRules.registryUrls`, which is a list, relying on the deb datasource's
`registryStrategy: "merge"`. It drops `suite=` from the annotations as a deliberate breaking change,
reasoning that a field which no longer steers anything is a false affordance.

That reasoning is sound and I would not reopen it. Two observations:

1. **It is necessary and not sufficient**, by its own admission (`design.md`, Risks: *"This change
   removes the cause, not the class"*). Shipping it alone repeats the #486→#532 pattern exactly: a
   correct config with no mechanism that notices when it becomes incorrect.
2. **It moves the suite fact from the Dockerfile into `renovate.json`**, which is the file *least*
   covered by any check in the repo (F7) — no workflow reads it, `gx.yml` excludes it, and its
   validator has zero call sites. The change is right, and it slightly increases the value of
   fixing F7.

---

## Options

The question is not "which fix", it is "what is the unit of work". Three framings:

| Approach | Pros | Cons |
|---|---|---|
| **A. Finish #532's plan as written** — ship #531, add `mode: full`, add a reconfigure-branch convention | Smallest diff; every item independently useful; #531 already in review | Item 2 is mis-framed (F1): `mode: full` constructs an incidental alarm, not a restored one. Leaves F6/F7 open — the Debian-14 recurrence is still armed. Repeats the #486 deferral shape |
| **B. #531 + observability, treated as one concern** — ship #531, `mode: full` as a *spec'd* out-of-band contract, and wire `renovate_validate.sh` into a real check | Closes the loop the archived design named and dropped (F8); follows the repo's own out-of-band convention (F10); modest scope | A config validator still would not have caught #486 or #532 (both were schema-valid, F7). Needs `renovate` pinned in `mise.toml` first |
| **C. Give the OS-package domain a manifest** — extend the `config/*.cue` + `cue vet` pattern (F9 Pattern A) to cover the suite set, the pins, and the base image's codename | Only option that disarms F6; makes suite a checked fact rather than prose in three places; makes a per-pin guard writable because the pin set becomes enumerable | Breaking; largest scope; touches `android.Dockerfile`, `config/`, `build.yml`; partly overlaps the separate Java-wiring PR |

```
  OPTION A                     OPTION B                     OPTION C
  ┌──────────────┐             ┌──────────────┐             ┌──────────────────┐
  │ renovate.json│             │ renovate.json│             │ config/*.cue     │
  │  packageRules│             │  packageRules│             │  suites + pins   │
  │  (#531)      │             │  + mode:full │             │  + base codename │
  └──────┬───────┘             └──────┬───────┘             └────────┬─────────┘
         │                            │                              │
         ▼                            ▼                     ┌────────┴────────┐
   correct today                correct today               ▼                 ▼
   unchecked                    + spec'd contract      renovate.json     cue vet in
   Debian 14 rearms it          + validator in CI      (derived)         build.yml
                                still unchecked                          ▲
                                per-pin                                  │
                                Debian 14 rearms it              Debian 14 fails loudly
```

---

## Recommendation

**Ship in this order: #531 → `mode` → observability. Treat C as the follow-up it deserves, and
file it now rather than deferring it into a design doc.**

Concretely, four changes, sequenced:

**1. Merge #531 as-is.** The diagnosis and the removal of `registryUrlTemplate` are correct. One
addition to its PR body: correct the #532 record on F1 (the `no-result` *is* debug-only; the WARN
is a rendering side effect that silent mode structurally precludes), since #531's own `proposal.md`
currently states "That line is logged at debug level" — which is right, and is what #532's
"correction" wrongly overturned.

**2. `"mode": "full"` in `.github/renovate.json`, plus a spec requirement.** F3 gives high
confidence this wins over Mend's env-injected default: `mode` is not `globalOnly`, repo config is
merged as the child, and neither `force` nor `dryRun` appears in the log. Push it on a
`renovate/reconfigure` branch so Renovate validates it. Verify on the next job log by the *absence*
of `Repository is running with mode=silent`.

Pair it with a requirement in `ci-repo-governance` following the `bypass_actors` precedent
(`spec.md:53-64`) — this is the repo's existing convention for out-of-band config (F10), and `mode`
is the last behavior-critical setting without one. State the composition hazard explicitly:
`automerge: true` + `mode=silent` means merges with no PR trail (F4).

**3. Make the pin set checkable.** This is F7/F8's debt. Two parts, both small:
- Wire `script/renovate_validate.sh` into a real job, with `.github/renovate.json` added to a
  `paths:` filter (`gx.yml:4-9` is the natural extension point, given gx already owns "what CI is
  allowed to look like").
- Assert per-pin resolvability, not just dependency count. The count guard the archived design
  proposed would **not** have caught #532 — all nine deps extracted fine; one resolved to nothing.

**Measured caveat on the validator (2026-08-08).** `renovate-config-validator --strict` catches
unknown options (`Invalid configuration option: notARealOption`) and wrong types (`packageRules`
not a list), but does **not** enforce `allowedValues`: `{"mode":"bogus"}` validates cleanly. It
also classifies `.github/renovate.json` as *global* config regardless of path. So it is worth
wiring as a cheap syntax gate, but it is not a correctness gate and must not be described as one.
Separately, pinning `renovate` via `mise` was attempted and abandoned: mise's supply-chain trust
policy blocks the install because `@yarnpkg/libzip@3.2.2` was hand-published by maintainer
`arcanis` without the SLSA provenance its `yarnbot`-published predecessors carried. Benign on
inspection (same person, listed maintainer), but not worth a trust exclusion for a local-only
convenience tool — the script keeps using `npx`.

**4. File C as an issue now.** The Debian-14 recurrence (F6) is armed and dated: when Debian 14
ships, `suite=stable` follows it and the pins do not. #531 pins codenames explicitly, which
converts the failure from *silent retarget* to *pins stop matching* — better, but still not
loud, and still requiring a hand-edit in lockstep with a Renovate-authored base-image bump. The
durable fix is a manifest, and the repo already has the pattern twice (F9). Filing it as an issue
rather than deferring it in a design doc is the direct lesson of F8.

```
  BEFORE                                   AFTER (1-3)

  renovate.json ──╳──▶ suite=stable        renovate.json ──▶ packageRules
       ▲                                        ▲              (codename URLs)
       │ no check                                │ validated, paths-filtered
       │ no spec                                 │ spec'd in ci-repo-governance
       │                                         │
  mode=silent (env, invisible)             mode: full (in-repo, reviewable)
       │                                         │
       ▼                                         ▼
  failure = absence of PRs                 failure = a check going red
  detected 10 weeks later by               ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  main going red                           (4) manifest ⇒ Debian 14 fails loudly
```

**On capability boundaries.** Do not file this under `linux-image-package-pinning`, which is scoped
to *how the Dockerfile is annotated* and would have to stretch to cover suites, base images, and
external-service config. #486 and #532 are the same class, and both sat *inside* that boundary while
crossing a different one. The better cut — supported by where the bugs actually recur — is a
capability owning **"config that steers an external service, and how it is validated"**, absorbing
the Renovate slices of the four specs in F11. Worth deciding at proposal time, not here.

---

## Open Questions

**Q1 — Does Mend's portal have a separate silent/Scan-Only toggle that re-forces `mode` on a later
run?** Renovate's OSS source proves repo config wins over a plain env key, and the log confirms no
`force`/`dryRun` (F3). But Mend's server-side config assembly is not in the OSS source, and Mend's
docs do not document override semantics for the "Scan Only" toggle — the gap that prompted
[discussion #39198](https://github.com/renovatebot/renovate/discussions/39198), which Mend left open
pending docs. *Tried:* Renovate source at `ecadb0c` (merge order, `force`, `dryRun`, `mode` option
flags), the job log's `File`/`CLI`/`Env`/`Combined` config records, renovatebot docs, Mend docs,
issue #26724, discussion #39198. *Resolves by:* reading the next job log after step 2 lands — one
line, no ambiguity.

---

## Next Steps

Run `/opsx:propose` for the `mode` + observability work (steps 2 and 3), which is the part with no
existing proposal. #531 already has its artifacts under
`openspec/changes/renovate-deb-registry-sets/` on its branch.

Before proposing, two decisions are yours:
- Whether steps 2 and 3 are one change or two. They are independently useful; step 3 is the larger
  and is what actually breaks the #486→#532 pattern.
- Whether to take the capability re-cut now (F11) or file the work under existing specs and re-cut
  later.
