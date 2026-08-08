# Research: making apt-pin resolution failure loud (issue #532, items 2 & 3)

Scope: issue #532 item 1 is done (PR #531). This researches the two open items:

- **Item 2** — make silent Renovate resolution failure loud.
- **Item 3** — decide whether to migrate openjdk-17 → openjdk-21.

Both are now resolved, neither as the issue framed them — see Headline. Findings
run F1–F10; F6/F6b/F7 cover the Java decision and its replacement, F10 the ARG
wiring that carries it.

## Headline

**Item 2 is already built — by Renovate, at WARN level, on the Dependency
Dashboard. It did not fire because the repository is running with `mode=silent`,
which suppresses the dashboard write entirely.** The issue's premise that
`no-result` is "logged at debug level only" is incorrect. Building a
network-dry-run CI guard would be reimplementing a mechanism the repo already
pays for and has switched off.

**`mode=silent` is the actual root cause of the ten weeks of silence, and it is
still on.** It also suppresses PR creation — two updates were withheld in the
2026-08-07 run alone. This outranks both items in the issue.

**Item 3 is decided: stay on openjdk-17. Do not migrate.** `flutter create`
scaffolds `sourceCompatibility = JavaVersion.VERSION_17`, and no Flutter source
publishes a recommended JDK above that floor. Flutter's `DEPS` pin to JDK 21 is
its *engine CI's* JDK ("required for running the formatter") — not a user-facing
recommendation. See F6. Bookworm therefore stays permanently, which makes PR #531
a permanent requirement rather than a stopgap.

**The replacement for item 3: derive the Java version from Flutter instead of
hand-maintaining it.** `config/version.json`'s `android.java.version` is currently
measured from the *previously published image*; it should be derived from the
Flutter version being built, like `gradle`/`buildTools`/`ndk` already are. The
signal to follow is Flutter's **enforced floor** (`errorJavaVersion` = 17), not the
`flutter create` template's `sourceCompatibility` — Flutter defines no recommended
or maximum Java version at all. See F6b.

**Carrying that value exposed a wider problem: adding any one manifest value costs
five file edits** (one hand-listed export plus four copy-pasted build-args blocks).
Making the manifest self-wiring turns Java into an ordinary field rather than a
special case. See F10.

---

## Context

What exists today, after PR #531 lands.

```
  android.Dockerfile                    .github/renovate.json
  ┌──────────────────────────┐          ┌─────────────────────────────┐
  │ # renovate: depName=curl │─────────▶│ customManagers[1]           │
  │ ARG CURL_VERSION="…"     │  regex   │   matchStrings              │
  │        × 9 pins          │          │   datasourceTemplate: deb   │
  └──────────────────────────┘          │                             │
                                        │ packageRules                │
  config/debian_12_bookworm.sources     │  ├─ deb → trixie ×3   (main)│
  ┌──────────────────────────┐          │  └─ openjdk-17 → bookworm ×3│
  │ Suites: bookworm …       │◀ ─ ─ ─ ─▶│       (4 components)        │
  │ Components: main contrib…│  "checkable  └─────────────────────────┘
  └──────────────────────────┘   by eye"              │
                                                      ▼
                                              deb.debian.org
```

Nine pins, all in `android.Dockerfile`: `curl:8`, `git:10`, `lcov:12`,
`ca-certificates:14`, `unzip:16`, `ruby-full:97`, `build-essential:99`,
`openjdk-17-jdk-headless:144`, `sudo:146`. Eight resolve against trixie; one
against bookworm, added solely because trixie has no openjdk-17
(`android.Dockerfile:149`).

The verification surface (11 workflows). `build.yml:372-444` holds three
hermetic, ~10s, no-`needs:` config jobs — `validate-version-files` (`cue vet`),
`validate-generated-config` (`update_test.sh` + `git diff --exit-code`),
`build-docs`. This is the repo's meta lane and its one verification idiom:
**commit two representations of a fact and diff them in CI** (used at
`build.yml:412-414`, `update-docs.yml:49-57`, `gx.yml:78-93`).

`script/renovate_validate.sh` runs `renovate-config-validator --strict`. It is
invoked by **nothing** — grep across all workflows, `mise.toml` and scripts
returns zero call sites. Its only references are `- [x]` checkboxes in change
documents (`openspec/changes/archive/2026-06-08-fix-renovate-dockerfile-pins/tasks.md:4`,
and PR #531's `tasks.md:23`). `.github/renovate.json` is the only significant
config file in the repo with no automated verification.

---

## Findings

### F1 — Renovate already surfaces this at WARN, on the dashboard

Traced through Renovate's source:

1. Lookup fails → `res.warnings.push({topic, message: 'Failed to look up deb package X: no-result'})`
   — `lib/workers/repository/process/lookup/index.ts:291-303`. The `logger.debug`
   at :295 that the issue cites is *adjacent to*, not instead of, the warnings push.
2. `getDepWarnings()` collects every `dep.warnings` and calls
   **`logger.warn({warnings, files}, 'Package lookup failures')`** —
   `lib/workers/repository/errors-warnings.ts:59-61`. **WARN, not debug.**
3. `getDepWarningsDashboard()` renders "⚠️ **Warning** Renovate failed to look up
   the following dependencies: … Files affected: …" — `errors-warnings.ts:112-138`.
4. It is written into the dashboard issue body at
   `lib/workers/repository/dependency-dashboard.ts:563-567`.

The only gate is `config.suppressNotifications?.includes('dependencyLookupWarnings')`
(`errors-warnings.ts:116`). **`.github/renovate.json` sets no `suppressNotifications`.**
Third-party dashboards confirm the rendered form in the wild, `no-result` included
— e.g. [trueforge-org/truecharts#18710](https://github.com/trueforge-org/truecharts/issues/18710).

So the correct-by-construction alarm existed the whole time and was not muted.

### F2 — Root cause: the repository is running with `mode=silent`

**Confirmed from the Mend job log** (`gmeligio_flutter-docker-image_2026-08-07_14-50_019fdc2a…log`,
Renovate 44.12.0, 173 lines). The log contains, verbatim:

```
level 30  Repository is running with mode=silent and will not make Issues or PRs by default
level 20  Silent mode enabled so repo is considered onboarded
level 20  Dependency Dashboard issue is not created, updated or closed when mode=silent
level 20  Config migration issues are not created, updated or closed when mode=silent
level 20  Branch renovate/debian-13.6-slim creation is disabled because mode=silent
level 20  Branch renovate/mcr.microsoft.com-windows-servercore-ltsc2025 creation is disabled because mode=silent
```

The lookup failure **did** occur in this run —
`Failed to look up deb package openjdk-17-jdk-headless: no-result` — and per F1 it
was pushed onto `dep.warnings`, destined for the dashboard. Silent mode discarded
the delivery.

```
  F1: the alarm fires ────────────────────────────┐
                                                  │
  lookup fails → dep.warnings → getDepWarnings()  │  logger.warn ✓
                       │                          │
                       ▼                          │
             getDepWarningsDashboard()            │
                       │                          │
                       ▼                          │
             dependency-dashboard.ts:563 ─────────┤
                       │                          │
                       ▼                          │
             ✗ mode=silent — issue not written ◀──┘  THE SILENCE
```

Corroborating detail: the log's own level histogram is **168 debug / 6 info /
zero WARN**. The `logger.warn('Package lookup failures')` at
`errors-warnings.ts:59-61` does not appear — consistent with the log being
captured at a level that elides it, or with silent mode short-circuiting before
the aggregation. Either way the operator-facing signal is absent from the log too,
so *neither* channel (dashboard nor log warning) carried it.

`mode` is set **outside the repository**. It is absent from `.github/renovate.json`,
absent from the log's `File config`, `CLI config` and `Env config` objects — so it
comes from Mend's per-repository settings at
[developer.mend.io/github/gmeligio/flutter-docker-image](https://developer.mend.io/github/gmeligio/flutter-docker-image).
That is why no amount of reading the repo could have found it, and why the
dashboard (issue #8) froze at 2026-07-12 while Renovate kept running.

**Blast radius is wider than the dashboard.** Silent mode also suppressed **two
pending updates** in this single run — `debian 13.6-slim` (digest) and
`mcr.microsoft.com/windows/servercore:ltsc2025`. Renovate computed them, then
declined to open branches. This is not only a lost alarm; it is a lost update
stream. Note PR #528 was opened 2026-08-06 and this run is 2026-08-07, so silent
mode was switched on inside that window — plausibly a deliberate quieting during
the #529 incident that was never switched back.

**This is a live misconfiguration, not a historical one.** Turning `mode` back to
its default is a settings change on the Mend portal, costs nothing, and restores
both the alarm and the updates.

### F3 — Eight of nine seams have no verification; the ninth fails by breaking main

```
 SEAM 1  annotation ─────────▶ regex match          ✗ nothing   (#317-class bug)
 SEAM 2  depName ────────────▶ real package?        ✗ nothing   (ruby-dev/full bug)
 SEAM 3  datasource ─────────▶ deb                  ~ schema only
 SEAM 4  registryUrls ───────▶ suites exist?        ✗ nothing   ← #532
 SEAM 5  archive lookup ─────▶ versions             ✗ in-repo   ← F1 covers this
 SEAM 6  PR opened ──────────▶ (absence invisible)  ✗ nothing
 SEAM 7  apt install ────────▶ docker build         ✓✓ LOUD — breaks main
 SEAM 8  .sources ↔ registryUrls                    ✗ nothing
```

Everything funnels through `.github/renovate.json` — seams 2, 3, 4 and 6 are all
*inside* it, and it is the one config file with no checker. Contrast `.github/gx.toml`,
an equivalent funnel, which has `gx lint` + `gx tidy` (`gx.yml:36-39,73-76`).

Note what a network dry-run guard would actually buy: it detects **seam 5**, the
one seam already covered loudly (by F1's dashboard warning, and by seam 7's build
failure). Seams 1, 2, 4 and 8 — where both real bugs happened — are
**config-vs-config** disagreements, catchable hermetically.

### F4 — Seam 8 is new, introduced by PR #531

`config/debian_12_bookworm.sources:5,11` and `renovate.json:37-39` now restate
the same three suites and four components. PR #531's own `design.md:66` calls this
"checkable by eye" — which is precisely the state seam 4 was in for ten weeks.
The trixie half (`renovate.json:26-30`) mirrors a sources file that exists only
*inside* `debian:13.6-slim`, so it is not even eye-checkable.

### F5 — gx is the wrong home

`gx 0.7.2` is a "CLI to manage Github Actions dependencies". `gx lint` has exactly
ten rules, all about `uses:` refs and workflow YAML security. Its inputs are
`.github/workflows/**`, `.github/actions/**`, `gx.toml`, `gx.lock`; its egress is
api.github.com. It has no concept of Dockerfiles, apt, deb, or datasources. The
boundary is already reasoned in
`openspec/changes/archive/2026-06-08-fix-renovate-dockerfile-pins/proposal.md:19`.
The memory "workflow lint belongs in gx" holds — this is not workflow lint.

### F6 — Item 3 decided: stay on openjdk-17

**Flutter publishes a floor and a template value, never a "recommended JDK."**
Three upstream sources, three different meanings — they must not be conflated:

| Source (at Flutter 3.44.9 / `6b182d2c`) | Value | What it actually means |
|---|---|---|
| `gradle_utils.dart` `errorJavaMinVersionAndroid` / `warnJavaMinVersionAndroid` | 17 | **Floor.** Errors below; no upper bound exists |
| `DependencyVersionChecker.kt` `warnJavaVersion`/`errorJavaVersion` | 17 | Same floor, checked downward only |
| **`flutter create` template** (`compileOptions.sourceCompatibility`) | **17** | **What a real Flutter app declares** ← the answer |
| `DEPS` → `flutter/java/openjdk` | 21 | **Flutter's engine CI JDK** — the inline comment says it is fetched "since java is required for running the formatter" |

**Correction to an earlier reading in this document:** the `DEPS` pin to 21 was
initially taken as evidence that 21 is "de-facto blessed." It is not. It is
Flutter's own build tooling, with no bearing on what users' apps should compile
against. `flutter create` — the closest thing to an official recommendation —
scaffolds **17**.

Java is also the only dependency in `gradle_utils.dart` with no
`maxKnownAndSupported*` constant. `oneMajorVersionHigherJavaVersion = '26'` is a
Gradle-compat bound, not a recommendation.

**Consequence:** migrating to openjdk-21 has no upstream basis. It would be a
maintainer divergence from what Flutter scaffolds, and would have to be documented
as such. Decision: **stay on 17.** Debian 12 bookworm therefore remains a permanent
part of the image, and PR #531's cross-suite packageRule is a permanent
requirement, not a stopgap that a migration would later delete.

Two consequences for earlier findings in this document: the openjdk-21 migration no
longer deletes the codename sprawl (F5-adjacent) or the seam-8 duplication (F4).
Both stand on their own merits and are **not** urgent — `mode: full` removes the
silence that made them dangerous.

For the record, since it motivated the original proposal: `openjdk-21-jdk-headless`
carries the *same* strict-equality sibling (`Depends: openjdk-21-jre-headless
(= 21.0.11+10-1~deb13u2)`), so migration would not have removed that hazard either
— only the cross-suite governance gap.

### F7 — Java representations, and which are guarded

Relevant regardless of the version shipped:

| Where | Mechanism | Guarded? |
|---|---|---|
| `android.Dockerfile:143-144` (the pin) | Renovate | by PR #531 |
| `android.Dockerfile:140` `JAVA_HOME` | **hand-typed** | **nothing** — TODOs at `:136-138` blocked on [moby/moby#29110](https://github.com/moby/moby/issues/29110) |
| `config/version.json:13-15` | derived backwards (F6b) | `cue vet` (shape only) |
| `config/schema.cue:46` | `java!: #PlatformVersion` — version-agnostic | static |
| `test/android.yml:34-40` | generated via `config/android.cue:33,56-61` | `build.yml:392-414` |

`readme.md` contains no `java`/`JDK`/`17`/`Debian` at all (grepped), and
`docs/build.mjs` has zero hits — so `android.java` currently feeds only the
`test/android.yml` self-assertion. The only real compatibility test is empirical:
`test/android.yml:3-21` runs `./gradlew bundleRelease` under the shipped JDK.

No JDK constraint is declared anywhere in the repo (grepped
`gradle|agp|kotlin|jdk|java` across all `.md`/`.cue`/`.json`/`.kts`/`.yml`).

### F6b — Replacement for item 3: derive the Java version from Flutter

`config/version.json`'s `android.java.version` is derived **backwards** today:
`update-version.yml:296-303` runs `script/java_version.sh` *inside the previously
published image*. It therefore describes the last build, not the next one, lags one
cycle by construction, and feeds nothing user-visible (`readme.md` never mentions
Java). Editing it changes nothing about what gets installed — it is a mirror
labelled as a dial.

**Which upstream signal to follow — resolved.** Three candidates were considered and
only one is both authoritative and machine-readable.

| Signal | Value | Verdict |
|---|---|---|
| `errorJavaVersion` / `errorJavaMinVersionAndroid` (**the floor**) | 17 | ✅ **Follow this.** The only value Flutter *enforces* |
| `flutter create` template `compileOptions.sourceCompatibility` | 17 | ✗ A *bytecode target*, not a JDK requirement, and user-editable |
| "Android recommended" | — | ✗ Not a Flutter concept (see below) |

**`compileOptions.sourceCompatibility` is the wrong signal**, despite reading `17`
today. It declares the bytecode level the app compiles *to*; JDK 21 can emit Java 17
bytecode via `--release`/toolchains. It matches only because the template author
picked the same number. It also lives in the generated app's `build.gradle.kts`,
which Flutter's own inline TODOs invite users to edit — so a user lowering it to
`VERSION_11` would "tell" the image to install a JDK that Flutter then hard-rejects.
Right answer today, wrong reason, silently wrong later.

**Flutter defines no recommended or maximum Java version.** Verified at
`3594a632` — `gradle_utils.dart` carries `maxKnownAndSupportedGradleVersion` (:85),
`maxKnownAndSupportedKgpVersion` (:91) and `maxKnownAndSupportedAgpVersion` (:98),
but **no `maxKnownAndSupportedJavaVersion`**. Only the floor exists, at
`gradle_utils.dart:72-73` and `DependencyVersionChecker.kt:99,101`, all four = 17,
with no warn band. The support policy is stated inline at
`DependencyVersionChecker.kt:87-91`:

> The following versions define our support policy for Gradle, Java, AGP, and KGP.
> Before updating any "error" version, ensure that you have updated the corresponding
> "warn" version for a full release to provide advanced warning.
> See flutter.dev/go/android-dependency-versions

That doc — *"Implementing a policy on supported AGP, KGP, Java, and Gradle versions
(PUBLICLY SHARED)"* — is a Google Doc behind a sign-in wall, so the source constants
are the readable form of the policy. `oneMajorVersionHigherJavaVersion = '26'`
(`gradle_utils.dart:78`) is **derived from Gradle, not Java** — per
`lib/src/android/README.md:76-78`, *"the Java version that is one higher than we
currently support … based on current maximum supported Gradle version."* So the real
ceiling is whatever Gradle/AGP accept. Java 21 works because Gradle 9.x does, not
because Flutter blessed it.

**Not evidence of a Java 21 recommendation:** `java_test.dart:314` (`'parses jdk 21
with patch numbers'`) is a *version-string parser* test — it asserts Flutter can turn
`"java 21.0.1"` into `Version(21, 0, 1)`. The same file tests 11 and 19. And `DEPS`
pinning `version:21` is the engine CI's JDK (F6).

**Follow the floor**, because it is the only value that is authoritative,
machine-readable, and moves on *Flutter's* cadence rather than ours. Tracking a
"recommended" version means the maintainer picks the number and re-litigates it every
release — the manual step this change exists to delete. Building on the floor is also
the safe direction for a CI image: 17 bytecode runs for everyone on 17+.

```
flutter/flutter @ pinned tag
      │
      ▼
DependencyVersionChecker.kt   ← errorJavaVersion = JavaVersion.VERSION_17
      │  (grep the constant from the SDK already in the container)
      ▼
config/version.json           ← android.java.version = 17
      │
      ▼
build-args ──▶ ARG android_java_version ──▶ JAVA_HOME + apt package name
```

Implementation note: `errorJavaVersion` is `internal` + `@VisibleForTesting` and
`checkDependencyVersions()` returns `Unit`, so there is **no API read** — the only
externally observable output is the boolean `usesUnsupportedDependencyVersions`
extra property, which says *that* something is out of range, never *what is
required*. So this is a text parse of the pinned checkout, matching the
upstream-parsing pattern `update-version.yml` already runs for the Windows vsman.
It breaks loudly if upstream moves the file (empty match → fail the step).

Pair it with a floor assertion in the Gradle task —
`check(JavaVersion.current() >= JavaVersion.VERSION_17)` — which is non-circular in
the useful direction: it fails the build if the installed JDK ever drops below what
Flutter enforces.

**Candidates rejected, with reasons:**

| Candidate | Why not |
|---|---|
| `compileOptions.sourceCompatibility` | Bytecode target, not a JDK requirement; user-editable (see above) |
| `JavaVersion.current()` / `java.version` | Fully circular — reports the JDK the Dockerfile already installed. Can verify, never determine |
| `flutter doctor` | Reports the *installed* JDK — circular, reproduces today's bug. No `--machine` flag |
| `flutter analyze --suggestions` | Returns a compatibility *verdict*, never a version; its validator sets `machineOutput => false` |
| `DEPS` | Wrong semantics (F6) — engine CI's JDK; would silently move the image to 21 |
| `releases_linux.json` | Contains no Java key |
| `usesUnsupportedDependencyVersions` property | Boolean violation flag; never carries the required version |

**Open design question:** should `readme.md` show Java? It currently never mentions
it. Once `version.json` is a real declaration, publishing it is nearly free.

### F8 — The log independently confirms PR #531's diagnosis

The 2026-08-07 run still had the pre-#531 config (`Post-massage config` shows the
old `{{#if release }}` template and the `suite=` capture group). Its
`getReleases statistics summary` reports all nine deb lookups against **one** URL:

```
"deb": { "count": 9, ... "registryUrls": {
   "https://deb.debian.org/debian?suite=stable&components=main,contrib,non-free&binaryArch=amd64": { "count": 9 }
}}
```

That matches the issue's own evidence exactly. After #531 this summary should list
multiple deb `registryUrl` entries — the acceptance test named in the PR. **Caveat:
under `mode=silent` the resulting PRs still will not be opened**, so #531's fix
cannot be observed end-to-end until F2 is resolved.

### F10 — Adding one manifest value costs five file edits

Discovered while designing F6b's wiring: adding `android.java.version` to the image
is not one edit but five, because the manifest→image path is hand-maintained at
every hop.

```
config/version.json
      │  ① hand-listed export
      ▼
script/setEnvironmentVariables.js     ← 10 explicit core.exportVariable calls
      │  ② copy-pasted build-args block × 4
      ▼
build.yml:158-164 · build.yml:180-186 · ci.yml:84-90 · release.yml:112-118
      │
      ▼
ARG in the Dockerfile
```

Each value is also renamed **three times** — `android.ndk.version` →
`ANDROID_NDK_VERSION` → `android_ndk_version` — with nothing checking the three
agree. A typo yields an empty ARG and a build that fails far from its cause.

**Proposal: make the manifest self-wiring.** Have `setEnvironmentVariables.js` walk
the manifest and derive ARG names mechanically from the JSON path, emitting the
entire build-args block as one output. Every workflow becomes:

```yaml
build-args: ${{ env.BUILD_ARGS }}
```

Adding a field then wires itself: put it in `version.json`, declare the `ARG`, done.
Java 17 stops being a special case and becomes an ordinary field — which is the
point.

**Layer-caching caveat.** Keep the derived-lowercase-name scheme rather than
collapsing to a single JSON blob: BuildKit still receives N distinct `--build-arg`
flags, so per-ARG cache granularity survives. Only *authoring* is centralized. This
matters — builds run 15–25 min and lean on registry buildcache
(`build.yml:151-152`); a fastlane bump must not rebuild the Flutter clone.

**Verified non-findings** (checked against a real CI run, not inferred):

- The `ANDROID_BUILD_TOOLS_VERSION: 30.0.3` job-level `env:` at `ci.yml:29` and
  `release.yml:42` is **not** shipping stale build-tools. `core.exportVariable`
  writes `$GITHUB_ENV`, which *does* override job-level `env:` for later steps.
  Run `31194164846` shows the flip mid-job and
  `--build-arg android_build_tools_version=36.0.0`. Dead 2022 leftovers
  (introduced in `b0414e4`) — delete for clarity, not urgency.
- `cmdlineTools` and `flutter.commit` are both consumed (`update_test.sh:10`;
  `update-version.yml:50,359`), contrary to a first-pass grep.

**Real adjacent findings, not in scope here:**

- **Nine scripts have zero call sites**: `jq_flutter_latest_version.sh`,
  `latest_android_ndk.sh`, `latest_android_sdk_platforms.sh`,
  `latest_android_sdk_command_line_tools.sh`, `container_structure_test.sh`,
  `docker_build_android.sh`, `build_windows.sh`, `update_changelog.sh`,
  `renovate_validate.sh`. The last should be **wired up**, not deleted (F3).
- **`cmdlineTools` pins nothing.** `update_test.sh:10-13` generates an assertion
  that the image contains `22.0`, while `android.Dockerfile:183` scrapes
  developer.android.com for whatever is *currently latest*. It passes by
  coincidence and breaks when Google ships 23.0 — a mirror labelled as a dial,
  the same defect as F6b's Java value.

### F9 — The `release` typo came from Renovate's own docs

The [deb datasource docs](https://docs.renovatebot.com/modules/datasource/deb/)
document exactly three parameters — `components`, `binaryArch`, `suite`. **There
is no `release` parameter.** Yet the docs' own Dockerfile example ships a
`registryUrlTemplate` with the same `{{#if release}}…{{else}}suite=stable{{/if}}`
fallback this repo had. The bug was inherited, not invented — worth an upstream
docs PR. Confirmed separately: `registryStrategy = 'merge'`
(`lib/modules/datasource/deb/index.ts:35`), so PR #531's multi-URL approach is
sound.

---

## Options

### For item 2 (make failure loud)

| Approach | Pros | Cons |
|---|---|---|
| **A. Turn off `mode=silent`** on the Mend portal | Root cause, now confirmed (F2). Restores the alarm *and* two suppressed updates. Covers all datasources. Zero code, zero CI cost. | Portal setting, not in-repo — invisible to code review and re-settable without a commit. Alarm is a GitHub issue body, so it needs someone to look. |
| **B. Network dry-run CI guard** (as the issue proposes) | Fails a PR, not a passive issue. | Duplicates F1. Detects only seam 5 — the one seam already loud twice over. First non-hermetic job in the meta lane; red when Debian's mirror is slow. Misses seams 1/2/4/8, where both real bugs actually were. |
| **C. Hermetic config-vs-config check** — generate `debian_12_bookworm.sources` and `renovate.json`'s `registryUrls` from one declared fact; `git diff --exit-code` | Uses the repo's existing idiom and lane. ~10s, no egress. Closes seams 4 and 8 by construction. | Cannot detect seam 5 (needs A or the build). New generator to maintain. |

A and C are complementary, not alternatives: A restores detection of "the archive
didn't answer"; C makes "the config disagrees with itself" impossible.

A has one genuine weakness worth naming: `mode` lives on the Mend portal, so
nothing in the repository records that it must stay off, and no PR can regress-test
it. That is an argument for *also* doing C — not for doing B, which is equally
blind to a portal setting.

### For item 3 — DECIDED: stay on 17 (table kept for the record)

| Approach | Pros | Cons |
|---|---|---|
| **Migrate to 21** | Deletes the bookworm suite entirely: the sources file, the COPY/rm, the packageRule, the rule-ordering constraint, seam 8, and the cross-suite governance gap. Drops an oldstable JDK's CVE surface. All 9 pins on one suite set. | Changes the JDK downstream users get — a product decision. `JAVA_HOME` (`:140`) is hand-typed and unguarded, so a typo there ships silently. Only empirical validation is `test/android.yml`. |
| **Stay on 17** | No downstream change. AGP 9 + Gradle 9.1 support 17 fine. | Keeps bookworm, the special-case rule, seam 8, and an oldstable JDK. Renovate must keep straddling two suite sets forever. |

---

## Recommendation

**Item 2 → Option A first, then C. Do not build B.**

```
  BEFORE (the issue's plan)          AFTER (recommended)
  ┌────────────────────────┐         ┌──────────────────────────┐
  │ new workflow           │         │ 0. turn OFF mode=silent  │
  │ npx renovate           │         │    on the Mend portal    │
  │ --dry-run=lookup       │         │    ← restores alarm +    │
  │ + egress to Debian     │         │      2 held-back updates │
  │ + minutes of CI        │         │                          │
  │ ────────────────────   │         │ 1. hermetic gen+diff in  │
  │ detects seam 5 only    │         │    build.yml meta lane   │
  │ (already loud ×2)      │         │    closes seams 4 & 8    │
  │ + STILL SILENCED by    │         │    ~10s, no egress       │
  │   mode=silent          │         │                          │
  └────────────────────────┘         └──────────────────────────┘
```

The issue's goal — "a pin that stops resolving fails loudly rather than going
quiet" — is met by A alone, for every datasource. B rebuilds it worse, and would
have been **silenced by the same setting**: a dry-run guard that reports through
Renovate's own channels inherits `mode=silent` too. Before any new guard is
designed, fix the one that was switched off.

**Item 3 → stay on openjdk-17; replace the item with a derivation (F6, F6b).**
`flutter create` scaffolds `VERSION_17` and no upstream source recommends higher.
Instead of migrating, fix the *provenance*: derive `android.java.version` from the
live `flutter create` toolchain, like `gradle`/`buildTools`/`ndk` already are. Fix
`JAVA_HOME` (`android.Dockerfile:140`) in that same change — it is the one Java
representation with no guard at all.

**PR #531 → continue, do not close.** It is clean, mergeable, and 12 checks green.
Its bug is live and independent of the Java decision: all nine pins resolve against
`suite=stable`, which follows whatever Debian calls stable and would silently
retarget every pin when Debian 14 ships. Staying on 17 makes bookworm permanent, so
#531's cross-suite rule is a permanent requirement rather than a stopgap that a
migration would have deleted. Two edits before merging: strike the "consider
openjdk-21" follow-up (now decided against, with F6's reasoning recorded so it is
not re-litigated), and note that the `{{#if release }}` example came from
[Renovate's own deb docs](https://docs.renovatebot.com/modules/datasource/deb/)
(F9) — no upstream PR for now. Its acceptance test cannot be observed until
`mode: full` lands, so sequence that first.

**Enforcing `renovate/reconfigure`.** Renovate validates a branch matching
`{{branchPrefix}}reconfigure` and posts a status to it
([docs](https://docs.renovatebot.com/config-validation/)), but only *"the next time
Renovate runs"* — the weekly schedule. It is a convention, not a gate, and nothing
forces the branch name. Record it as a short rule in `CLAUDE.md` / `AGENTS.md`; if a
hard gate is wanted, that is `script/renovate_validate.sh` in `build.yml` filtered to
`paths: ['.github/renovate.json']`. Caveat if both are used: reconfigure does not run
config migration first, so legacy option names can fail there while passing `--strict`.

Since the openjdk-21 migration is off, two earlier findings no longer get deleted
for free and stand on their own merits, neither urgent: the Debian codename stated
~21 times across 4 files and defined nowhere (`config/schema.cue:41-57` has no
Debian concept), and PR #531's new seam-8 duplication (F4). `mode: full` removes the
silence that made both dangerous.

---

## Open Questions

1. **Why is `mode=silent` set, and was it intentional?** The log proves *that* it
   is set and that it comes from Mend's per-repository settings (absent from the
   repo config and from the log's `File`/`CLI`/`Env` config objects). Timing —
   PR #528 opened 2026-08-06, silent run 2026-08-07 — suggests it was switched on
   during the #529 incident. Whether that was deliberate, and whether anything
   still depends on it, is a maintainer/portal question not answerable from the
   repo or the log.

2. **Should `readme.md` publish the Java version?** It currently never mentions
   Java (grepped), so nothing documents JDK 17 to users, though downstream
   Flutter/AGP builds consume it at runtime. Once F6b makes `version.json` a real
   declaration, publishing it is nearly free. Maintainer call.

3. **Does the Dockerfile pin follow the derived value automatically, or gate on
   it?** The major version is welded into the ARG *name*
   (`OPENJDK_17_JDK_HEADLESS_VERSION`), so a future 17→21 move is a rename plus a
   suite change, not a value bump. Recommended shape in F6b: derive `version.json`,
   fail CI loudly on divergence, keep the migration itself a deliberate human
   change. Needs a design pass.

4. **Not verified: does Mend's hosted app honour repo-level `mode`?** Precedence is
   stated as design intent in
   [renovatebot/renovate#26724](https://github.com/renovatebot/renovate/issues/26724)
   ("if the user configures mode=remediation in renovate.json then it would override
   anything set by the app in global config") and matches Mend's documented
   "set `mode: full` in the repos you want to go full" pattern. The next job log
   settles it: if it still reports `mode=silent` after the config merges, Mend is
   forcing the value and the portal is the only lever.

---

## Next Steps

Settled decisions: **stay on openjdk-17** (F6), **derive it from Flutter's enforced
floor `errorJavaVersion`, not the template's `sourceCompatibility`** (F6b), **make
the manifest self-wiring** (F10), **continue PR #531**, **`mode: full` in
`.github/renovate.json`**, **no upstream docs PR** (note it in #531 instead).

Two independent tracks. Renovate is separate from the Java/wiring work and does not
gate it:

**Track A — Renovate (separate change)**

| # | Change | Notes |
|---|---|---|
| A1 | `"mode": "full"` in `.github/renovate.json` | Small PR, on branch `renovate/reconfigure` |
| A2 | Merge PR #531 | After A1; its acceptance test is only observable once silent mode is off |
| A3 | `renovate/reconfigure` rule in `CLAUDE.md` / `AGENTS.md` | Convention, not a gate |

**Track B — Java 17 + ARG wiring (this proposal)**

| # | Change | Notes |
|---|---|---|
| B1 | Self-wiring build-args (F10) | Derive ARG names from the manifest; collapse 4 copy-pasted blocks to `${{ env.BUILD_ARGS }}`. Keep per-ARG flags for layer caching |
| B2 | Derive Java from `errorJavaVersion` (F6b) | Grep the constant from the pinned Flutter checkout; delete `script/java_version.sh` and `update-version.yml:296-303` |
| B3 | Wire `android_java_version` into the Dockerfile | Replaces hand-typed `JAVA_HOME` (`:140`) and the apt package name; move `ARG` above the `ENV` block |
| B4 | Floor assertion in the Gradle task | `check(JavaVersion.current() >= JavaVersion.VERSION_17)` |

B1 lands first so B2/B3 add a field rather than a special case.

Also worth doing once: comment on #532 recording F2 — the issue's stated root cause
("logged at debug level only") is wrong, and the correction matters for anyone
reading it later.

Deliberately out of scope, recorded in F10 for a later change: nine dead scripts,
the `cmdlineTools` mirror, and the dead `30.0.3` job-env lines.
