# Research: why Renovate did not update the stale openjdk pin (#555)

Source log: `gmeligio_flutter-docker-image_2026-08-27_20-55_94d07cb1-9275-4315-b8f9-029e71ac7d0c.log`
(Mend-hosted Renovate 44.46.0, run at 2026-08-27T20:55Z, repo SHA `7dc0aa2`).

## Answer up front

Renovate did not update the pin because **it never had an update to offer**. It looked
the package up, got a result it considered authoritative, and concluded the pin was
current. The issue's hypothesis — "the manager is not matching this ARG" — is wrong:
the ARG *is* matched, extracted, and looked up successfully.

The real cause is that `17.0.20+8-1~deb12u1` **has never existed in any suite the image
enables**. It is not a stale pin. It is a fabricated one, hand-transcribed from an apt
error message in PR #529.

The precise mechanism, proven by a cache-cold local run (§4): Renovate **did** download
the bookworm index and **did** read the real version `17.0.19+10-1~deb12u2` out of it —
but `17.0.20 > 17.0.19` under deb versioning, so the fabricated pin sorts *above* the
entire archive. Renovate proposes upgrades only, never downgrades, so a pin above the
archive ceiling is indistinguishable from a pin that is current. Renovate can detect
"a newer version exists"; it has no concept of "this version does not exist", and
neither does this repo.

## Context

```
  android.Dockerfile:142                   config/debian_12_bookworm.sources
  ┌────────────────────────────┐           ┌────────────────────────────────┐
  │ # renovate: depName=       │           │ Suites: bookworm               │
  │   openjdk-17-jdk-headless  │  mirrors  │         bookworm-updates       │
  │ ARG OPENJDK_17_JDK_        │◀─ ─ ─ ─ ─▶│ Components: main contrib       │
  │   HEADLESS_VERSION="…"     │  by eye   │   non-free non-free-firmware   │
  └────────────┬───────────────┘           └────────────────────────────────┘
               │                                          ▲
     extracted by customManager                  mirrors by eye
               ▼                                          │
  ┌────────────────────────────────────────────────────────────┐
  │ .github/renovate.json:33-42  packageRules[openjdk-…]       │
  │   registryUrls: [bookworm, bookworm-updates,               │
  │                  bookworm-security]                        │
  └────────────────────────────────────────────────────────────┘
```

Three independent statements of one fact — which apt suites this image enables — held in
agreement only by prose in two `description` fields (`renovate.json:25`, `:34`).

## Findings

### 1. Renovate extracted the dep and reported no update

From the run's `packageFiles with updates` payload (log line 93):

```json
{
  "depName": "openjdk-17-jdk-headless",
  "datasource": "deb",
  "currentValue":   "17.0.20+8-1~deb12u1",
  "currentVersion": "17.0.20+8-1~deb12u1",
  "fixedVersion":   "17.0.20+8-1~deb12u1",
  "registryUrl": "https://deb.debian.org/debian?suite=bookworm&components=main,contrib,non-free,non-free-firmware&binaryArch=amd64",
  "homepage": "https://openjdk.java.net/",
  "warnings": [],
  "updates": []
}
```

`warnings: []`, `updates: []`, and a resolved `homepage` — Renovate is confident. This is
the *opposite* of the #486/#531 failure mode, which logged `no-result` at debug level.

### 2. The pinned version exists in no suite the image enables

Independently verified against Debian's own archive:

```
$ curl https://api.ftp-master.debian.org/madison?package=openjdk-17&table=all
openjdk-17 | 17.0.12+7-2~deb11u1  | oldoldstable | source
openjdk-17 | 17.0.19+10-1~deb12u2 | oldstable    | source   ← bookworm has THIS
openjdk-17 | 17.0.20~7ea-1        | unstable     | source
openjdk-17 | 17.0.20+8-1          | unstable     | source   ← sid only, no ~deb12u1
openjdk-17 | 17.0.20.1+1-1        | unstable     | source
```

`17.0.20+8-1~deb12u1` appears nowhere. The `~deb12u1` suffix denotes a bookworm backport
upload that was never published under that name. The correct bookworm version is
`17.0.19+10-1~deb12u2` — **the value the pin held before PR #529 changed it**
(`git log -L` on `android.Dockerfile`, commit `424f731`).

### 3. Provenance: the value was transcribed from an error message

PR #529 (merged 2026-08-07) says so explicitly:

> The target version is taken from the failing build's own apt output, which named
> `17.0.20+8-1~deb12u1` as the version available for `openjdk-17-jre-headless` in that
> exact repository set. […] This could not be confirmed locally (the dev sandbox has no
> egress to `deb.debian.org` and no Docker daemon) — **CI on this PR is the verification.**

CI could not verify it: every build path uses a warm cache (`build.yml:156`,
`ci.yml:82,130`, `release.yml:112`), so the `apt-get install` layer was never re-executed.
The PR went green without ever evaluating the pin — the known cold-build-drift pattern.

What apt reported was a transient candidate for `openjdk-17-jre-headless` from
`bookworm-security`, before that upload was superseded. It was never installable as
`openjdk-17-jdk-headless` from the enabled suite set.

### 4. Then why does Renovate *agree* with a version that doesn't exist?

**Not because the lookup failed.** A cache-cold local run of the same Renovate version
(44.46.0) against the same repo settles this — it *did* fetch bookworm, successfully:

```
1 x https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages.gz -> 200
```

The downloaded index was inspected directly out of Renovate's own cache:

```
$ grep -A15 '^Package: openjdk-17-jdk-headless$' <cached-index>.txt | grep -m1 '^Version:'
Version: 17.0.19+10-1~deb12u2
```

So Renovate held the correct bookworm version in memory and still emitted `updates: []`.
The reason is **version ordering**, not reachability:

```
$ node -e "... versioning/deb ... isGreaterThan('17.0.20+8-1~deb12u1','17.0.19+10-1~deb12u2')"
true
```

`17.0.20 > 17.0.19`, so the fabricated pin sorts *newer* than everything the archive
offers. Renovate only proposes upgrades, never downgrades — a pin ahead of the real
archive is indistinguishable from a pin that is simply current. This is the whole
mechanism, and it is silent by construction.

```
  pin  17.0.20+8-1~deb12u1   (does not exist anywhere)
        ^ sorts ABOVE
  real 17.0.19+10-1~deb12u2  (bookworm, what apt installs)

  Renovate: "nothing newer" -> updates: []   <- correct behavior, wrong premise
```

The earlier reading of the Mend log's `skip` counters as "bookworm was never fetched" was
wrong: `skip` there means the package cache answered, and the cold run proves the
underlying fetch works. **The bug is not that Renovate cannot see bookworm. It is that a
fabricated pin above the archive ceiling is invisible to an upgrade-only tool.**

### 5. Separately: 4 of 6 configured registryUrls are unreachable

Independent of #555, the cold run recorded exactly **34 HTTP 404s and 34
`"Skipping component due to an error"`** — a 1:1 match. Per-URL tally:

```
39 x .../dists/trixie-updates/main/binary-amd64/Packages.gz          -> 404
39 x .../dists/trixie-security/main/binary-amd64/Packages.gz         -> 404
 3 x .../dists/bookworm-updates/{main,contrib,non-free*}/...gz       -> 404
 3 x .../dists/bookworm-security/{main,contrib,non-free*}/...gz      -> 404
 1 x .../dists/trixie/main/binary-amd64/Packages.gz                  -> 200
 1 x .../dists/bookworm/{main,contrib,non-free,non-free-firmware}    -> 200
```

**Single cause: Renovate hardcodes `Packages.gz`.** Not a path problem —
`packages.ts` contains the literal
([source](https://github.com/renovatebot/renovate/blob/main/lib/modules/datasource/deb/packages.ts)):

```ts
const compression = 'gz';   // not a parameter, not configurable
```

Debian stopped publishing `.gz` on the delta suites; they carry only `Packages` and
`Packages.xz`:

| URL | `.gz` | `.xz` |
|---|---|---|
| `dists/trixie/main/binary-amd64/` | **200** | 200 |
| `dists/bookworm/main/binary-amd64/` | **200** | 200 |
| `dists/trixie-updates/main/binary-amd64/` | 404 | 200 |
| `dists/bookworm-updates/main/binary-amd64/` | 404 | 200 |
| `dists/trixie-security/main/binary-amd64/` | 404 | **200** |
| `dists/bookworm-security/main/binary-amd64/` | 404 | 200 |

Note the security rows: the path `dists/<suite>/main/binary-amd64/` is **correct as
configured**. The `Release` file declares `Components: updates/main ...`, but the actual
on-disk layout is plain `main/` — setting `components=updates/main` was probed and returns
**404**. The earlier suggestion to change the security components was wrong; there is
nothing to fix in the path.

**Can `*-updates` be configured differently to work? No.** Verified exhaustively:

- Not a component-name problem — every component 404s identically on `.gz`.
- Not a mirror problem — `ftp.debian.org`, `ftp.us.debian.org`, `archive.debian.org`,
  and `mirror.csclub.uwaterloo.ca` all return 404 for `bookworm-updates/.../Packages.gz`.
  Debian no longer publishes it anywhere.
- Not exposed as an option — the compression is a hardcoded `const` with no config path.

Upstream confirms this is a known, unfixed gap:
[issue #44330](https://github.com/renovatebot/renovate/issues/44330) —
*"hardcoded `Packages.gz` breaks repos serving plain `Packages` or `Packages.xz`"* (open,
filed 2026-07-01), with [PR #35865](https://github.com/renovatebot/renovate/pull/35865)
("Support deb indices compression") open since 2025-05-11 and still unmerged.

**Conclusion: no config change can make `*-updates` or `*-security` resolve.** The only
paths are to wait for PR #35865, or to drop the four dead URLs and document why.

```
  CONFIGURED (6)                    ACTUALLY REACHABLE (2)
  |------------------|              |------------------|
  | trixie           |-----200---------->gt| trixie           |
  | trixie-updates   |--404 .gz--x  |------------------|
  | trixie-security  |--404 .gz--x
  | bookworm         |-----200---------->gt|------------------|
  | bookworm-updates |--404 .gz--x  | bookworm         |
  | bookworm-security|--404 .gz--x  |------------------|
  |------------------|
     all 34 failures swallowed at debug level; job still "successful"
```

Practical impact is small but real: security-only uploads to `*-security` are invisible to
Renovate. It is *not* the cause of #555.

### 6. The model gap: "stale" and "nonexistent" are the same state

|  | **Stale pin** | **Nonexistent pin** |
|---|---|---|
| Meaning | Resolves; newer exists | Resolves to nothing |
| Renovate | Opens a PR | `updates: []`, no warning |
| Cold build | Succeeds | `E: Version '…' was not found` |
| Modelled in this repo? | Yes — the whole pinning capability | **No** |

`openspec/specs/linux-image-package-pinning/spec.md:131-156` reads as though it covers
this, but every scenario asserts *where Renovate looks*, never *that the lookup returned
anything*. Renovate's silence is overloaded: it means either "your pin is current" or
"your pin does not exist," and the repo reads it as health.

This exact guard was already identified and deferred —
`openspec/changes/archive/2026-08-09-renovate-deb-registry-sets/proposal.md:54`:

> **A CI guard that fails when a pin resolves to nothing.** This is the *only* thing that
> would catch the one genuinely silent failure mode […] The guard that works asserts every
> deb pin yields a lookup result, which needs a network dry-run against `deb.debian.org`.

Related: **#536** (open) — `OPENJDK_17_JDK_HEADLESS_VERSION` hardcodes `17` while
`android.Dockerfile:162` interpolates the derived `${android_java_version}`. #536 predicts
the collision bites when Flutter's Java floor moves; #555 shows the *patch* half rots on
its own, a mode #536 does not enumerate — the pin has no owner who would notice.

## Options

| Approach | Pros | Cons |
|---|---|---|
| **A. Repin by hand to `17.0.19+10-1~deb12u2`** | Unblocks cold builds today; one-line | Fixes nothing structural; #529 already did exactly this and produced #555 |
| **B. A + drop the 4 dead registryUrls** | Config stops encoding a false coverage claim; 34 silent 404s per run disappear | Cosmetic w.r.t. #555 — those URLs are not the cause; loses `-security` visibility that was never actually working |
| **C. B + CI guard asserting every deb pin exists in the archive** | Closes the actual gap; catches both #555 and the ten-week #486 bug | Network dry-run in CI; own cost/flakiness; the deferred work from `proposal.md:54` |

## Recommendation

**C, staged — but A first and immediately**, since `main` cannot cold-build.

The guard must check **existence**, not just "an update was offered". Renovate's silence
cannot distinguish the two, which is exactly how #555 survived. Concretely: for each
pinned `depName`/version, assert the exact version string appears in the archive index for
an enabled suite — a downgrade-aware check, not an upgrade check.

```
  BEFORE                                  AFTER
  |-------------|                         |-------------|
  | hand-typed  |                         | archive-    |
  | pin from    |--> sorts ABOVE archive  | sourced pin |--> exists in index
  | apt error   |    Renovate: updates:[] |-------+-----|
  |-------------|         |                      |
         |                v                      v
         |          no warning at all      |-----------------|
         v                                 | CI guard: pin   |
  cold build FAILS                         | must EXIST in   |--> red PR if
  weeks later, on                          | an enabled suite|    absent
  an unrelated PR                          |-----------------|
```

Sequencing:

1. **Repin** to `17.0.19+10-1~deb12u2`, verified against the archive (not against an apt
   error message). Note in the PR that the value was checked via ftp-master madison.
2. **Drop the 4 unreachable registryUrls** (`*-updates`, `*-security`), with a comment
   citing renovate#44330 — they cannot resolve until upstream supports `.xz`, and leaving
   them in encodes a coverage claim that is false. Revisit when PR #35865 merges.
3. **Add the resolution guard** (`proposal.md:54`), asserting *existence*. This is the
   only step that makes "nonexistent pin" a named, checked state rather than an invisible
   one. A working prototype already exists: parse the `# renovate: depName=` / `ARG …` pairs
   out of `*.Dockerfile`, fetch `dists/<suite>/main/binary-amd64/Packages.gz` for the
   enabled suites, and assert each pinned version string appears verbatim. Run against the
   current tree it flags exactly one dep — `openjdk-17-jdk-headless` — and passes the
   other 13.

Step 3 is where the value is. Without it, the next hand-edited pin repeats #555 —
this is already the second occurrence. Steps 1 and 2 alone would leave the exact failure
mode of #555 fully reachable.

Note: step 2 touches `.github/renovate.json`, which per project convention must go on a
branch named `renovate/reconfigure` — so it cannot share a PR with step 1.

A cold-build CI leg would also have caught it, and is worth weighing against the guard:
cheaper to reason about, far more expensive to run. The guard is narrower and targets the
actual defect.

## Open questions

Both prior open questions are now closed by the cache-cold run (§4, §5):

- ~~Can `-updates` be covered from config?~~ **No.** `packages.ts` hardcodes
  `const compression = 'gz'` with no config path; Debian publishes no `.gz` on the delta
  suites on any mirror. Blocked on upstream
  [renovate#44330](https://github.com/renovatebot/renovate/issues/44330) /
  [PR #35865](https://github.com/renovatebot/renovate/pull/35865).
- ~~Does the package cache mask a current bookworm failure?~~ **No.** The cold run fetched
  `dists/bookworm/main/.../Packages.gz` → 200 and parsed the correct version out of it.
  Bookworm resolution is healthy; the defect is version ordering, not reachability.

Remaining:

- **What should the guard do about a pin that is *newer* than the archive?** #555 is that
  case. Treating it as an error is right for this repo, but the check has to be explicit
  about direction — an "is it resolvable" check passes on a too-new pin.
- ~~Does the same failure mode affect the trixie pins?~~ **No.** All 13 trixie pins were
  checked against the downloaded trixie index by exact version-string match: every one is
  present (`curl 8.14.1-2+deb13u4`, `git 1:2.47.3-0+deb13u1`, `clang 1:19.0-63`, …).
  `openjdk-17-jdk-headless` is the only defective pin in the repo.

## Next steps

Run `/opsx:propose` on this change to turn the staged plan into a proposal. Steps 1 and 2
are small enough to share one PR; step 3 warrants its own.
