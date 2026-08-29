# Research: sync flutter-windows Docker Hub description (issue #521)

Source issue: https://github.com/gmeligio/flutter-docker-image/issues/521

## Summary of what changed since the issue was filed

The issue is partly stale. Two of its three load-bearing claims no longer hold:

| Issue claim | Status today | Evidence |
| --- | --- | --- |
| Only `flutter-windows` lacks a description | **Wrong** — `flutter-linux` lacks one too | Docker Hub API, below |
| `readme.md` makes "no mention of the Windows platform" | **Wrong** — readme covers Windows fully | `readme.md:3,7,27-31,50,70-75` |
| "The only cause is the missing matrix entry" | **Wrong** — it was a recorded, accepted trade-off | `openspec/changes/archive/2026-05-20-p2-release-windows-image/design.md:66-67` |

Live Docker Hub state (`curl https://hub.docker.com/v2/repositories/gmeligio/<name>/`):

```
flutter-android    full_description: 5370 chars   short: "Docker images for Flutter Continuous Integration (CI)"
flutter-web        full_description: 5370 chars   short: "Docker images for Flutter Continuous Integration (CI)"
flutter-linux      full_description: NULL         short: (none)
flutter-windows    full_description: NULL         short: "Docker images for Flutter CI in Windows platform"
```

`flutter-linux` shipped in #551 on 2026-08-24, after the last tag `3.47.1`
(2026-08-20), so it has never been through a release run. It *is* already in
both matrices (`release.yml:191`, `:243`), so its NULL resolves on the next tag
with no code change. **`flutter-windows` is the only one that stays NULL
forever.**

Note the fourth cell: `flutter-windows` has a *hand-set, tailored* short
description. See "Regression the issue does not mention" below.

---

## Context

What exists today. `release.yml` (324 lines, 6 jobs) spans build, verify,
describe, scan, and GitHub-release:

```
  tag push
     │
     ├──▶ release-linux ──────────────┐   matrix: android, web, linux   (release.yml:36-41)
     │      (android.Dockerfile)      │   + target axis — legitimately excludes Windows
     │                                │
     ├──▶ release-windows ────────┐   │   uses: windows-image.yml       (release.yml:117)
     │      (windows.Dockerfile)  │   │   no `outputs:` block at all
     │                            │   │
     │                            ▼   ▼
     ├──▶ verify-published   needs: [release-linux, release-windows]     (release.yml:142)
     │      matrix: android, web, linux, WINDOWS  ✅                     (release.yml:152-156)
     │
     ├──▶ update-description  needs: release-linux                       (release.yml:181)
     │      matrix: android, web, linux — WINDOWS MISSING ❌             (release.yml:189-191)
     │
     ├──▶ record-image        needs: release-linux                       (release.yml:233)
     │      matrix: android, web, linux — WINDOWS MISSING ❌             (release.yml:241-243)
     │
     └──▶ create-github-release  needs: release-linux                    (release.yml:285)
            per-VERSION, not per-image — the comment at :286-288 admits it
```

Three of the five downstream jobs hang off `release-linux` not because they
depend on it, but because there is nothing else to attach to.

---

## Phase 0 findings

### Step 1 — The model

**"Published image" is not a first-class concept anywhere.**
`config/version.json` — the declared single source of truth, guarded by
`config/schema.cue` via `.github/actions/validate-version-manifest` — models
tool *versions* and contains zero image entities.
`script/setEnvironmentVariables.js:88-90` takes `IMAGE_REPOSITORY_NAME` as an
env *input* and concatenates `owner/name`; it never knows what images exist.

So the image set is re-spelled by hand in ~12 places:

| # | Location | Members | Shape |
|---|---|---|---|
| 1 | `build.yml:52-57` | android, web, linux | `name`+`target` |
| 2 | `build.yml:215-220` | android, web, linux | `name`+`config` |
| 3 | `build.yml:290-292` | android, web, linux | `name` |
| 4 | `release.yml:36-41` | android, web, linux | `name`+`target` |
| 5 | `release.yml:152-156` | **all four** ✅ | bare list |
| 6 | `release.yml:189-191` | android, web, linux ❌ | degenerate `include:` |
| 7 | `release.yml:241-243` | android, web, linux ❌ | degenerate `include:` |
| 8 | `cleanup-pr-image.yml:33-35` | android, web, linux | bare list (Windows absence *commented*, :26-28) |
| 9 | `docker-compose.yml` | 7 services | stage-oriented |
| 10 | `docs/build.mjs:44` | **all four** ✅ | the only list-as-**data** |
| 11 | `test/` filenames | four, two harnesses | implicit |
| 12 | `openspec/specs/generated-docs-and-examples/spec.md:31` | **three** ❌ | prose |

Plus scalar re-spellings at `ci.yml:21`, `prepare-release.yml:32`,
`update-version.yml:323`, `build.yml:441`, `update-version.yml:241`,
`windows-image.yml:39`.

**Only `docs/build.mjs:44` treats the set as data — and it is in the
documentation layer, the one place with no authority over CI.** The irony: the
readme is the *most* correct model of the image set in the repo; CI is the
least.

**How Windows got dropped.** Matrices #6 and #7 are `include:` lists with a
single `name` key and no second axis — a degenerate form that only exists
because it was copy-pasted from #4, which genuinely needs `target`. #4
legitimately excludes Windows (different Dockerfile, different runner). #6/#7
inherited that exclusion as an accident. **A build fact was silently converted
into a publication policy.**

**Naming collision.** `linux` means the Flutter *target platform* in
`flutter-linux` (`android.Dockerfile:240` `FROM flutter AS linux`) but the
*host OS* in `release-linux` (`release.yml:22`) — the same job uses "linux" in
the host sense while producing `flutter-linux` in the target sense. The repo
compensates with prose ("Linux-hosted image": `build.yml:46`,
`cleanup-pr-image.yml:26`, `readme.md:35`). The `linux-image-*` specs mean the
host base, not `flutter-linux`.

**Windows is modeled as an exception, not a member.** `cleanup-pr-image.yml:26-28`
documents Windows' absence with a justified reason. `release.yml:189-191` and
`:241-243` omit it with **no comment at all** — an unmarked gap vs. a marked one.

**The omission was a deliberate, recorded trade-off** —
`openspec/changes/archive/2026-05-20-p2-release-windows-image/design.md:66-67`:

> - **[Trade-off] No Docker Hub description update for the Windows image.** →
>   Acceptable: users discover the Windows variant via the GitHub README… A
>   separate Docker Hub repo (`flutter-windows`) will appear bare for now.
> - **[Trade-off] No Scout scan / SARIF upload for Windows.** → Acceptable: the
>   Scout coverage gap on Windows base images is well-known.

The model has **no place to record that a deliberate exclusion has expired**.
Its stated justification ("users discover via the GitHub README") was written
when the README was Android-centric; the README now covers Windows as a
first-class platform, so the premise is gone but the exclusion remains.

### Step 2 — The structure

**No interface exists between "an image was built" and "downstream per-image
work".** No workflow that builds an image emits a job output.
`windows-image.yml:6-26` declares `workflow_call` inputs and secrets but **no
`outputs:` block**, so `release-windows` cannot report what it published even
in principle. The only connective tissue is `needs:` edges plus hand-copied
matrix literals.

The repo already diagnosed this for one job and routed around it rather than
fixing it — `release.yml:137-141`:

> "Did it publish?" is read from the registry by an anonymous pull, never
> inferred from which release job succeeded — that coupling is what let this
> job drift before.

`verify-published` is the fixed sibling. `update-description` and `record-image`
are the un-fixed ones — the same drift, same file, still live.

**The chokepoint is per-image-*name*, not per-image-*set*.**
`setEnvironmentVariables.js` resolves one name a caller already knows. Nothing
can answer "which images does this release publish?"

**`.github/actions/` is the established boundary pattern.** Three composite
actions exist — `build-linux-image` (owns the build call and every build arg,
shared by 4 legs), `clean-runner-disk`, `validate-version-manifest` — all
cross-cutting per-concern boundaries, and one (`linux-image-build-boundary`) is
spec'd with the exact principle this issue needs:

> The step that builds the Linux image SHALL be defined once, as a composite
> action under `.github/actions/`. Every workflow step that builds
> `android.Dockerfile` SHALL use it rather than restate the build inline.

`build-linux-image/action.yml` documents *why* composite over reusable
workflow (needs job-local state) — a constraint that does **not** apply to a
description sync, which needs only a repo name and a file. The repo is
mid-migration toward named boundaries, **but only for builds**. Publication
concerns were never given the same treatment.

**`readme.md` conflates two documents.** `docs/build.mjs:5` says so outright:
"The same readme.md is used as the GitHub README and the Docker Hub
description." One 5370-char file describing all four images gets pushed to four
per-image repos, so a `flutter-web` visitor's page carries an Android badge and
a Windows workflow snippet. `build.mjs:28-30` already carries a workaround
forced by the conflation (absolutize every in-repo link to github.com because
relative links don't resolve on Docker Hub).

**The spec directory shows the same confusion.** Release is spec'd *per-image*
(`web-image-release`, `windows-image-release`; no `android-image-release` or
`linux-image-release` exists at all), while verification of the same publish is
spec'd *per-concern* (`ci-image-anonymous-availability`). The description sync
has no spec of its own — it is one stray sentence inside a **docs-codegen**
spec (`generated-docs-and-examples/spec.md:5-7`). A publication requirement is
filed under documentation generation because publication has no spec home.

That same spec has itself drifted: line 31 mandates coverage of "**every
published image** — `flutter-android`, `flutter-web`, and `flutter-windows`"
(three named, `flutter-linux` missing), and its scenario is titled "All three
images are presented from the manifest" (`:51`) while `build.mjs:44` generates
four. **A hand-spelled enumeration drifted inside the very spec that mandates
non-drift.** `ci-image-anonymous-availability/spec.md:6-8` is likewise stale
(names only android and windows).

---

## Findings

### The single correct invariant already exists in one spec

`ci-image-anonymous-availability/spec.md:6`:

> The set of verified pairs SHALL be exactly the set the run published.

That is the invariant every downstream per-image job needs, and it is stated
once, for the one job that gets Windows right. Generalizing it is the whole fix.

### Regression the issue does not mention

The action PATCHes both fields. From
`peter-evans/dockerhub-description/src/dockerhub-helper.ts`:

```ts
const body = { full_description: fullDescription }
if (description) { body['description'] = description }
```

`release.yml:224` passes `short-description: ${{ github.event.repository.description }}`
= `"Docker images for Flutter Continuous Integration (CI)"` — always non-empty.
The `flutter-windows` Docker Hub page currently carries a hand-set, tailored
short description: `"Docker images for Flutter CI in Windows platform"`.

**Adding the matrix entry as-written silently overwrites that with the generic
repo description.** A net loss on the one axis where the Windows page is
currently *better* than the others. `short-description` is capped at 100 bytes
(`src/main.ts:7`) and truncated with a warning.

### The two omissions are not the same kind of thing

| | `update-description` | `record-image` (Scout) |
| --- | --- | --- |
| Mechanism | pure HTTP PATCH, no image pull | Scout analysis of a Windows image |
| Windows blocker | **none** — `readme-filepath` and `repository` are per-invocation inputs (`action.yml`) | **Scout does not support Windows images** (maintainer decision) |
| Trade-off premise | **expired** (README now covers Windows) | **still valid** |
| Disposition | add Windows | **keep Windows excluded, permanently** |

`docker/scout-action` is invoked with `registry://` (`release.yml:265`), a
remote analysis with no local pull, so a `windows-2025` runner would not have
been required — but that is moot: Scout does not support Windows images, so
`record-image` stays a three-image job.

**This is a durable asymmetry, not a gap.** It is the reason the image set
cannot be a flat list of names: membership differs per concern. `flutter-windows`
is in `verify-published` and `update-description` but not `record-image` (Scout
unsupported) and not `cleanup-pr-image` (no PR push, `cleanup-pr-image.yml:26-28`).
Whatever models the set must carry **per-image capability flags**, and the
Windows/Scout exclusion must be *marked as deliberate* — the unmarked gap at
`release.yml:241-243` is precisely what made this issue ambiguous.

### Same defect class is already open as issue #544

https://github.com/gmeligio/flutter-docker-image/issues/544 — `ci-image-handoff`
hardcodes `flutter-android` where a set belongs, and its body records the same
history: `cleanup-pr-image.yml` named only `flutter-android`, so every closed PR
left a `flutter-web` orphan behind — **32 accumulated** before anyone noticed.

That is the cost curve of this defect class, already paid once. #521 and #544
are the same bug in two different enumerations.

---

## Decisions taken (maintainer, 2026-08-27)

These are settled and close the two open questions this research raised:

1. **The matrix entry and the image-set-as-data model ship in the same change
   and the same PR.** Not sequenced across two PRs.
2. **Docker Scout does not support Windows images.** `record-image` keeps
   `flutter-windows` excluded — permanently, and now marked as deliberate
   rather than left as an unmarked gap.
3. **The tailored Windows short description is kept**
   (`"Docker images for Flutter CI in Windows platform"`). The sync must not
   overwrite it with the generic repo description.
4. **`config/images.json` takes the full shape** — it carries `testConfig` and
   `prTag` as well as the fields the two release matrices need, so the same
   change also retires `build.yml`'s three enumerations and
   `cleanup-pr-image.yml`'s one. #544 closes with #521.

Decision 2 is what makes decision 1 tractable: because membership differs per
concern, the data model cannot be a flat name list — which is exactly the thing
a one-line matrix fix would have papered over.

---

## Options

Options A (matrix entry alone) and B (set as data) are no longer alternatives —
decision 1 merges them. What remains open is the **shape** of the data and
where it lives.

```
  B1 — extend version.json          B2 — new config/images.json
  ┌────────────────────────┐        ┌────────────────────────┐
  │ config/version.json    │        │ config/version.json    │  versions
  │   flutter: {...}       │        ├────────────────────────┤
  │   android: {...}       │        │ config/images.json     │  identity
  │   images: [...]  ◀─new │        │   [{name, target,      │
  └────────────────────────┘        │     scout, ...}] ◀─new │
   one file, two kinds of fact      └────────────────────────┘
```

| Approach | Pros | Cons |
| --- | --- | --- |
| **B1. `images` array inside `config/version.json`** | One manifest. `docs/build.mjs:16` and `update-docs.yml:18` already read/watch it — no new wiring. | Conflates two kinds of fact: the file is a *version* manifest (`schema.cue`'s root is `#Version`, and every existing key is a tool version). A tag bump would touch the same file as an image-set change. |
| **B2. New `config/images.json` + `#Images` in `schema.cue`** ✅ | Keeps `version.json` version-only. The image set is a different fact with a different change cadence. `validate-version-manifest` already runs `cue vet`, so guarding a second file is a one-line extension. | Second file to wire: `docs/build.mjs` needs a second `readFileSync`, and `update-docs.yml:18` needs it added to the `paths:` filter or docs drift goes undetected. |
| **C. Per-image Docker Hub descriptions from `build.mjs`** | Fixes the real user-facing defect — every image's page currently describes all four. `readme-filepath` is per-invocation so it is supported today. | Separate concern from #521; four new generated files. **Out of scope — own issue.** |

---

## Recommendation

**One PR: the matrix entry and the image-set model together, using B2.**

```
  BEFORE — 12 enumerations           AFTER — one manifest, filtered per concern

  release.yml                         config/images.json
   ├ :36-41   android, web, linux       [{ name, target, shortDescription,
   ├ :152-156 all four ✅                  scout, testConfig, prTag }]
   ├ :189-191 android, web, linux ❌               │ fromJSON
   └ :241-243 android, web, linux ❌   ┌────────────┼────────────┐
  build.yml                            ▼            ▼            ▼
   ├ :52-57   android, web, linux    release.yml  build.yml   cleanup-pr-image
   ├ :215-220 android, web, linux     ├ build      ├ build     └ where prTag
   └ :290-292 android, web, linux     ├ verify     ├ test
  cleanup-pr-image.yml:33-35          ├ describe   │  where testConfig
  docs/build.mjs:44  all four ✅       └ record     └ scan
       (only one as DATA)                where scout   where scout
                                                 │
                                                 ▼
                                          docs/build.mjs (reads it)

  update-description                  update-description
    needs: release-linux                needs: [release-linux, release-windows]
    matrix: android, web, linux         matrix: all four
                                        short-description: per-image
  record-image                        record-image
    matrix: android, web, linux         matrix: where scout == true
      (unmarked gap)                      → still three, now MARKED deliberate
```

**Scope of the single PR:**

1. **`config/images.json`** — the image set as data, in the **full shape**
   (decision 4), carrying every per-image property currently scattered across
   the enumerations:

   | Field | Consumer | Windows value |
   | --- | --- | --- |
   | `name` | all matrices | `flutter-windows` |
   | `target` | `build.yml:52-57`, `release.yml:36-41` | *(absent — different Dockerfile)* |
   | `shortDescription` | `update-description` | `"Docker images for Flutter CI in Windows platform"` |
   | `scout` | `record-image`, `build.yml:290-292` | `false` — Scout does not support Windows images |
   | `testConfig` | `build.yml:215-220` | *(absent — Pester, `test/windows/Windows.Tests.ps1`, not container-structure-test)* |
   | `prTag` | `cleanup-pr-image.yml:33-35` | `false` — `windows.yml:20` builds with `push: false` |

   Guard it with an `#Images` definition in `config/schema.cue`; extend
   `.github/actions/validate-version-manifest` to `cue vet` it. CUE is a good
   fit for the shape: `target` and `testConfig` are required *iff* the image
   builds from `android.Dockerfile`, which is expressible as a disjunction
   rather than left to convention.

   `prTag` is genuinely data, not derivable at the point of use: whether an
   image pushes a handoff tag is decided by `push: false` hardcoded in
   `windows.yml:20`, a *different workflow file* that `cleanup-pr-image.yml`
   cannot read. Encoding it removes the guesswork that left 32 orphaned tags
   (#544).

2. **`release.yml`** — a `setup`-style job emits the list as a `fromJSON`
   matrix output. This pattern already exists at `build.yml:22-27`. Drive
   `update-description` (all four) and `record-image` (`scout == true` → three)
   from it.
2b. **`build.yml` and `cleanup-pr-image.yml`** — retire their four remaining
   enumerations against the same manifest: the build matrix (`:52-57`), the
   test matrix (`:215-220`, keyed on `testConfig`), the scan matrix
   (`:290-292`, filtered on `scout`), and the cleanup matrix
   (`cleanup-pr-image.yml:33-35`, filtered on `prTag`). Both `build.yml`
   comments already say "Mirror the build matrix" (`:210`, `:285`) while
   hand-copying it — this makes the mirror real.
3. **`needs: release-linux` → `needs: [release-linux, release-windows]`** on
   `update-description` (`release.yml:181`). Without it the Windows leg can sync
   a description for an image whose build failed — the exact coupling
   `release.yml:137-141` documents as the prior drift cause.
4. **Per-image `shortDescription`**, preserving
   `"Docker images for Flutter CI in Windows platform"` (decision 3). The action
   sends `description` whenever non-empty, so the generic repo description must
   stop being the source. Cap is 100 bytes (`src/main.ts:7`).
5. **Mark the Scout exclusion** in `images.json` as a flag with a comment
   naming the reason (Scout does not support Windows images), converting an
   unmarked gap into a recorded decision — the thing `design.md:66` had no home
   for.
6. **`docs/build.mjs:44`** reads `images.json` instead of its own literal, and
   `update-docs.yml:18` gains `config/images.json` in its `paths:` filter.

This closes #521 and #544 together — they are the same defect in two
enumerations — and applies the repo's own stated principle
(`linux-image-build-boundary`: "SHALL be defined once, as a callable unit") to
publication instead of builds.

**Spec work in the same PR:** the description sync needs a per-concern spec home
rather than a sentence in `generated-docs-and-examples`. Note in the PR body
that the archived trade-off (`design.md:66`) is reversed for the description
(its premise — README does not cover Windows — has expired) and **upheld** for
Scout (`design.md:67`).

**Out of scope, own issue:** per-image Docker Hub descriptions (Option C).

**Spec work required either way.** The description sync needs a per-concern
spec home rather than a sentence in `generated-docs-and-examples`. Three
existing specs are stale and should be corrected as part of whichever PR
touches them:

- `generated-docs-and-examples/spec.md:31,51` — names three images, generator makes four
- `ci-image-anonymous-availability/spec.md:6-8` — names android + windows only, workflow verifies four
- `windows-image-release/spec.md:65,82` — says `release-android` / `needs: release-android`; the workflow now says `release-linux`

---

## Open Questions

None. Both questions this research raised were answered by the maintainer
decisions above:

- *Does Scout support Windows images?* → **No.** `record-image` stays
  three-image; the exclusion becomes a marked flag rather than an unmarked gap.
- *Keep the tailored Windows short description?* → **Yes.** The sync carries a
  per-image `shortDescription`.

The `images.json` shape question is settled as the full shape (decision 4).

**One risk to carry into the proposal, not a blocker.** The full shape puts
`build.yml` in the diff — the PR-critical path and the largest workflow (488
lines). A defect in the two release matrices surfaces on the next tag; a defect
in `build.yml` breaks every PR immediately. The mitigation is ordinary and
available: `build.yml` runs on `pull_request`, so the PR that changes it
exercises it. Confirm the build, test, and scan legs all still enumerate three
images on the PR's own run before merging.

---

## Next Steps

Run `/opsx:propose` on `sync-published-image-descriptions` — this research is
already in place at
`openspec/changes/sync-published-image-descriptions/research.md`. The proposal
covers the single PR described in the Recommendation, closing #521 and #544.

Open one follow-up issue: per-image Docker Hub descriptions (Option C), so each
image's page stops describing all four.
