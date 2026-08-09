# Research: maintainer devex & long-term maintenance cost of PR #531

Topic: does [PR #531](https://github.com/gmeligio/flutter-docker-image/pull/531)
("fix(renovate): resolve apt pins against every suite the image enables") have
the best devex for a maintainer in terms of design, and can the solution be
simplified to reduce long-term maintenance?

Status at time of research: PR #531 open, draft, branch
`claude/flutter-docker-build-failure-vs3sjg`, one commit `6cffc57` on top of
`0bc825f`. Change `renovate-deb-registry-sets`, 16/17 tasks done (4.5 is a
post-merge check).

## Context

The image installs nine pinned apt packages. Which versions exist depends on the
set of apt suites each build stage enables. That set is stated in four places,
none of which knows about the others:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │ WHERE THE APT SUITE SET IS WRITTEN DOWN                          │
  ├──────────────────────────────────────────────────────────────────┤
  │                                                                  │
  │ (a) android.Dockerfile:1  FROM debian:13.6-slim@sha256:...       │
  │       └─ implies trixie / trixie-updates / trixie-security,      │
  │          components=main.  NEVER WRITTEN DOWN ANYWHERE.          │
  │          Bumped unattended by Renovate's docker manager.         │
  │                                                                  │
  │ (b) config/debian_12_bookworm.sources:1-13                       │
  │       └─ bookworm / -updates / -security,                        │
  │          components=main,contrib,non-free,non-free-firmware      │
  │          COPY'd at android.Dockerfile:150, deleted at :169       │
  │                                                                  │
  │ (c) .github/renovate.json:23-41  (added by THIS PR)              │
  │       └─ both families again, as 6 registryUrl query strings     │
  │                                                                  │
  │ (d) design.md:8-19 — the apt-get output, transcribed as prose    │
  └──────────────────────────────────────────────────────────────────┘
```

Before the PR, suite selection lived in a `registryUrlTemplate` on the deb
custom manager, branching on `{{#if release }}` while `matchStrings` captured a
group named `suite`. The conditional always fell through, so all nine pins
resolved against `suite=stable`. Eight worked by coincidence (trixie *is*
stable); `openjdk-17-jdk-headless` resolved to `no-result` for ten weeks at
debug log level and then broke `main`.

## Findings

### 1. The PR's core mechanical judgement is correct

`registryUrlTemplate` renders one string, and the deb datasource takes one suite
per URL — only `components` is comma-split, and `-security` sits under a
different base path (`/debian-security`). apt's candidate is the max across
*every* enabled suite. A one-URL mechanism therefore cannot express what
correctness requires. Removing it rather than repairing the `{{#if release }}`
typo is the right call: repairing it would still miss `bookworm-security`, where
`~deb12uN` security uploads land first — reproducing the exact skew that broke
the build.

Deleting `suite=` from the annotations is right for the same reason the design
gives (`design.md:58-62`): an inert field is a false affordance, and a false
affordance is precisely what hid this bug.

### 2. The model gap: the apt environment is not a first-class concept

The PR moves duplication from `registryUrlTemplate` into `packageRules`. It does
not remove the duplication. And the duplication is now asymmetric:

| Suite family | Declarative file in repo | Mirrored in renovate.json |
|---|---|---|
| bookworm | `config/debian_12_bookworm.sources` | yes, stanza-for-stanza |
| trixie | **none** — implied by `FROM` | yes, but mirrors nothing checkable |

The trixie half of `renovate.json:24-30` is the only written record of the base
image's suites. It can only be verified by pulling the image. Meanwhile Renovate's
docker manager bumps `FROM debian:13.6-slim` unattended (see `8476e0c`,
`d301c28`, `3ca7c22`). When Debian 14 lands, `registryUrls` still says `trixie`
and every pin silently stops resolving — **the same silent-failure class this PR
just fixed, one dimension over.** `design.md:71` calls that drift "loud"; the
evidence says it is exactly as quiet as the bug being fixed, because
`no-result` is a debug-level line.

### 3. Rule order is semantics, and nothing checks it

`renovate.json:23-31` and `:32-41` are distinguished only by array position. A
later matching rule *replaces* `registryUrls`. The constraint is recorded in a
`description` string and in `design.md:54-56` — prose, not a test.
`renovate-config-validator --strict` is syntax-only (already in memory:
`feedback_renovate_validator_limits`) and will happily pass a reordered array.

### 4. `script/renovate_validate.sh` is orphaned

The whole script is one line:

```
npx --yes --package renovate -- renovate-config-validator --strict
```

Grepped the repo: referenced only from openspec markdown (`design.md:89` and the
archived `2026-06-08-fix-renovate-dockerfile-pins`). No workflow, no mise task,
no docs instruction runs it. **Renovate config has zero CI coverage today** —
even the syntax check is manual.

### 5. Codegen would be over-engineering — verified, not assumed

Tempting idea: the repo already has manifest→codegen→staleness-gate machinery
(`config/version.json` + `config/schema.cue` + `mise run docs` +
`update-docs.yml:47-57` + `build.yml:392-432`, adopted in
`2026-06-18-single-version-source-of-truth`). Why not generate `renovate.json`'s
registryUrls from it?

Because the manifest does not model the OS at all. `grep -in "debian|apt|suite"
config/schema.cue config/version.json` returns nothing. `FROM debian:13.6-slim`
is bumped by Renovate's docker manager entirely outside the `version.json` path.
Generating registryUrls would require inventing a `debian` block in the manifest
*and* rewiring the docker-manager bump into `update-version.yml` (22 KB of
workflow). Against 2 packageRules and 6 URLs, that is over-engineering by an
order of magnitude.

Also: `.github/` is hand-written by convention here. `gx.toml` is hand-maintained
(`gx.lock` is the generated artifact); `docs/contributing.md:89` tells humans to
hand-edit `.github/renovate.json`. Generated output lands at repo root,
`examples/`, `test/` — never `.github/`. **The PR putting registryUrls in
`renovate.json` by hand matches repo convention exactly.**

```
  WHAT THE PR FIXED            WHAT IT LEFT OPEN
  ┌──────────────────┐         ┌──────────────────────────────┐
  │ pin → wrong      │         │ FROM debian:13 → 14 bump     │
  │ suite (silent)   │  FIXED  │   ⇒ registryUrls stale       │
  └──────────────────┘         │   ⇒ pins no-result (silent)  │
                               ├──────────────────────────────┤
                               │ packageRules reordered       │
                               │   ⇒ override dead (silent)   │
                               └──────────────────────────────┘
                                  same failure class, unguarded
```

## Options

| Approach | Pros | Cons |
|---|---|---|
| **A. Merge as-is** | Correct today; smallest diff; matches `.github/` hand-written convention | Leaves trixie set unrecorded; Debian 14 bump re-creates the silent failure; rule order unchecked; validate script stays dead |
| **B. As-is + two additive closes** (declarative trixie sources file; wire `renovate_validate.sh` into `mise run lint` + CI) | ~10 lines, no new machinery; both halves of the deb rules mirror a checked-in file; kills the orphan script; gives the Debian 14 bump an obvious file to edit next to the `FROM` | Trixie file is documentation-only (not `COPY`'d); syntax-only validator still won't catch semantic drift |
| **C. Generate registryUrls from a manifest** (`debian` block in `version.json` → CUE → renovate.json, git-diff gate) | Single source of truth; order emitted by construction | Requires new manifest dimension + rewiring `update-version.yml`; violates the `.github/`-is-hand-written convention; ~order of magnitude cost vs 6 URLs |

```
  OPTION A                OPTION B                    OPTION C
  ┌────────────┐          ┌────────────┐              ┌──────────────┐
  │ renovate   │          │ *.sources  │              │ version.json │
  │  .json     │          │  (x2)      │              └──────┬───────┘
  │ (6 URLs)   │          └─────┬──────┘                     │ cue
  └────────────┘                │ mirrored by eye            ▼
       ▲                        ▼                     ┌──────────────┐
       │ implied by       ┌────────────┐              │ renovate.json│
  FROM debian:13          │ renovate   │              │ (generated)  │
   (unwritten)            │  .json     │              └──────────────┘
                          └─────┬──────┘                 + git-diff gate
                                │                        + update-version
                          mise run lint ──▶ CI             rewire
```

## Recommendation

**Merge PR #531 essentially as it stands — Option B.** The design is right, and
it is right for reasons the design doc argues correctly. Do not restructure it,
and specifically do not generate `renovate.json`: the manifest has no OS
dimension, and adding one costs far more than it saves for six URLs.

Two additive closes were proposed here. **Both were later revised — read the
addendum below before acting on either.** Recorded as written, for the reasoning
trail:

1. ~~**Add `config/debian_13_trixie.sources`**~~ — *rejected.* Implemented, then
   deleted. Nothing would read the file, so it could not make any invariant
   checked, and the bookworm half *was* mirrored throughout the ten weeks the
   bug ran. See the addendum.
2. **Wire `script/renovate_validate.sh` into `[tasks.lint]` in `mise.toml`** —
   *adopted, without the CI job.* The script was dead code and, at mode 644
   versus 755 for every script CI runs, could not even be executed. It stays
   local: Renovate config changes ship on a `renovate/reconfigure` branch where
   the Renovate app validates the config and reports back, so a workflow running
   the same validator would duplicate the authoritative check.

```
  BEFORE (PR as-is)                    AFTER (as shipped)
  ┌──────────────────┐                 ┌──────────────────────┐
  │ trixie: unwritten│                 │ trixie: FROM line    │
  │ bookworm: .sources│                │ bookworm: .sources   │
  └────────┬─────────┘                 └──────────┬───────────┘
           │                                      │ co-update noted in
           ▼                                      ▼ the rule description
  ┌──────────────────┐                 ┌──────────────────────┐
  │ renovate.json    │                 │ renovate.json        │
  └──────────────────┘                 └──────────┬───────────┘
       (no check at all)                          ▼
                                        mise run lint (local only;
                                        renovate/reconfigure covers CI)
```

On devex specifically: the annotation grammar after this PR is
`# renovate: depName=curl` above `ARG CURL_VERSION`. That is as simple as the
annotation can get without deriving `depName` from the `ARG` name entirely — a
possible future simplification, out of scope here, and worth noting the
annotation was never the right home for suite data in the first place.

## Follow-ups already recorded in the PR

- CI guard asserting every deb pin resolves (needs network dry-run against
  `deb.debian.org`). Re-motivated: extraction succeeded here and *resolution*
  failed afterwards, so the deferred "assert ≥1 deb dependency extracted" guard
  would not have caught this. **Deliberately not built yet** — see the addendum:
  the deb manager has never once run with both known defects fixed, so there is
  no baseline to guard. Read the first post-merge job log first.
- openjdk-17 → trixie openjdk-21 migration. This deletes
  `config/debian_12_bookworm.sources`, the cross-suite pin, the override
  packageRule and this whole bug class — the single largest long-term
  maintenance reduction available. Product decision; correctly out of scope.
  Note `depName=openjdk-17-jdk-headless` can never propose it: `openjdk-21-*` is
  a different package name, so no config change makes this visible to Renovate.

## Open Questions

None that research could not settle. The one thing not verifiable pre-merge is
the post-merge job-log check (>1 deb `registryUrl`, and no `no-result` for
`openjdk-17-jdk-headless`) — egress to `deb.debian.org` is blocked in the
sandbox, so only URL construction is locally checkable. Deferred out of the
change; see "Deferred verification" in `tasks.md`.

## Addendum: failure-mode analysis (supersedes the trixie-sources recommendation above)

Follow-up research on "what would actually catch this?" overturned recommendation
(1). The sources file was implemented, then deleted. Two distinct failure modes
were conflated in the original write-up:

| Failure mode | Silent? | Caught by |
|---|---|---|
| Base image moves to a new Debian release; `registryUrls` still name the old suites | **No** | The PR build fails. Apt pins are exact-version (`curl="$CURL_VERSION"`), those versions are absent from the new release, `apt-get install` errors, and `build.yml` builds both targets on every PR |
| `registryUrls` name a suite that never resolves, while pinned versions still install | **Yes** | Nothing. `no-result` is debug-level; build stays green. The ten-week `openjdk-17-jdk-headless` bug |

Precedent settles the first row: `4cddcea` is the Debian **12→13 major** bump. It
merged with a human co-author beside `renovate[bot]` and rewrote every pin
(`7.88.1-10+deb12u14` → `8.14.1-2`), retargeted the annotations
(`release=bullseye` → `suite=trixie`), created
`config/debian_12_bookworm.sources`, and edited `renovate.json` — all in one PR.
A Debian major bump is not a quiet one-line change.

The decisive argument against the sources file: **the bookworm half *was*
mirrored** by `config/debian_12_bookworm.sources` for the entire ten weeks the
bug ran, and mirroring caught nothing. A file nothing reads cannot catch a
failure. It would be a second copy to keep in sync, offering no signal beyond
`android.Dockerfile:1`. Deleted; the co-update instruction moved into the trixie
rule's `description`, where the URLs are actually edited.

Only the second row needs machinery, and only a lookup-result assertion with
network egress to `deb.debian.org` provides it — the deferred follow-up, now
with a sharper justification.

## Next Steps

Fold the two Option B additions into PR #531 (or open a small follow-up change),
then mark #531 ready for review.
