# Research: manifest-build-arg-wiring

Re-examination of the existing change against the current tree. Two of the
change's load-bearing premises are stale, and the structural investigation
points at a different boundary than the one the change targets.

## Context

`config/version.json` reaches a Docker build through exactly one conduit: a
single emitter writing a flat, process-global environment namespace.

```
                          config/version.json
                                   │
                                   ▼
                  script/setEnvironmentVariables.js
                     (11 hand-written exports)
                                   │
                                   ▼
                           $GITHUB_ENV  ◀── flat, process-global
                                   │
       ┌───────────┬───────────┬───┴────┬───────────┬──────────┐
       ▼           ▼           ▼        ▼           ▼          ▼
   build.yml   build.yml    ci.yml  release   release:198  windows-
   push path   fork path            :100-121  prepare-rel   image.yml
       │           │           │        │      update-ver      │
       └───────────┴─────┬─────┴────────┘                      │
                         ▼                                     ▼
         docker/build-push-action                  PowerShell array
         build-args: (7 lines × 4 copies)          (5 --build-arg pairs)
                         │                                     │
                         ▼                                     ▼
                 android.Dockerfile                  windows.Dockerfile
```

Seven call sites invoke one emitter. Three of them (`release.yml:208`,
`prepare-release.yml:52`, `update-version.yml:390`) need exactly **one**
variable and receive **twelve**. A call site cannot declare what it needs.

## Findings

### F1 — The change's motivating defect no longer exists

`proposal.md:9-13` and `spec.md:29-32` rest on: *"`android.java.version` sits in
the manifest but reaches no build."*

That is **false as of commit `0c9b3ff` (PR #537)**. Verified wiring:

| Layer | Location |
|---|---|
| Export | `script/setEnvironmentVariables.js:34` |
| Passed | `build.yml:161`, `build.yml:184`, `ci.yml:87`, `release.yml:117` |
| Declared | `android.Dockerfile:137` |
| Consumed | `android.Dockerfile:139` (`JAVA_HOME`), `:162` (apt package name) |
| Asserted | `config/android.cue:60`, via `script/update_test.sh:16` |

The consequence is not merely an artifact edit. The defect was fixed **without**
this change — which is direct evidence that the five-edit cost is tolerable, and
removes the proposal's "that cost has already caused a defect" argument.

Counts are also off by one throughout: there are **seven** manifest-derived build
args per block, not six (`design.md:4`, `tasks.md:1,4,17`).

### F2 — `GIT_VERSION` collision, and the change would arm it

Two unrelated things share one name in a flat namespace:

```
  windows.git.version = "2.55.0"          android.Dockerfile:10
  (Git for Windows)                       ARG GIT_VERSION=
         │                                  "1:2.47.3-0+deb13u1"
         ▼                                  (Debian apt pin, Renovate-owned)
  setEnvironmentVariables.js:38                      ▲
  exports GIT_VERSION into $GITHUB_ENV               │
         │                                           │
         └── present in EVERY Linux build job ───────┘
                    (collision is one line away)
```

Safe today by **two accidents**: `build-push-action` forwards only explicitly
listed args, and no Linux block lists `git_version`. Docker ARG names are
case-sensitive, so `git_version` ≠ `GIT_VERSION`.

The hazard is that `tasks.md:7` places `windows.git.version → git_version` in the
**same table** the Linux legs would consume via `${{ env.BUILD_ARGS }}`, while
`tasks.md:4` says the emission is "restricted to the Linux build's six
manifest-derived arguments." **These two tasks contradict each other**, and
neither `spec.md` nor `design.md` specifies a per-target partition.

Critically, an unmatched `--build-arg` is a **warning, not an error**
([docker/buildx#2704](https://github.com/docker/buildx/issues/2704)) — so if the
partition is got wrong, nothing fails. It fails silently.

`docker-compose.yml:7-55` reads the same namespace, a second exposure path.

### F3 — Provenance is the missing concept

Every pinned version has an owner. The repo has no name for that property,
encoding it **positionally** (which file) and **typographically** (ARG casing):

| Owner | Cadence | Home |
|---|---|---|
| Renovate | weekly | Dockerfile ARG defaults (UPPERCASE + quoted default) |
| Flutter release feed | weekdays | `version.json` `flutter` block |
| Live `flutter create` | on Flutter bump | `version.json` `android`, `fastlane` |
| VS / Git-for-Windows | on Flutter bump | `version.json` `windows` |
| Human | never | `windows11Sdk.build`, `cmdlineTools.version` |

The casing is not stylistic — `.github/renovate.json:61` regex-matches
`ARG .*?_VERSION="`, making it a machine-read discriminator. One exception proves
it is an accident rather than a contract: `windows.Dockerfile:8`
`ARG git_installation_path="C:\Program Files\Git"` is lowercase *with* a default
and belongs to neither population.

`config/version.json` is really *"versions Renovate does not own"* — a negative
definition with no name. That unnamed axis is what makes the `GIT_VERSION`
collision possible.

### F4 — `build-args:` is ~16% of the duplication

Comparing the four Linux legs **in full**, not just their build-arg lines:

```
  Per-leg duplication (~45 lines)
  ┌────────────────────────────────────────────┐
  │ harden-runner · checkout · setEnvVars(9)   │
  │ clean-runner-disk · setup-buildx           │
  │ Docker Hub login · GHCR login              │
  │ metadata-action · build-push-action        │
  │ file: · target:                            │
  │ ┌────────────────────────────────────────┐ │
  │ │ build-args: (7 lines)  ◀── the change  │ │
  │ └────────────────────────────────────────┘ │
  └────────────────────────────────────────────┘
```

The legs differ only in cache backend (`build.yml:151` registry vs `ci.yml:107`
gha), output mode (`push`/`outputs=docker`/`load`), attestations
(`build.yml:149-150` only), registry set (`release.yml:93` adds Quay), and tag
source — all expressible as `workflow_call` inputs.

The already-drifted parts are the *other* blocks (`release.yml:78`
`buildkitd-flags: --debug`; `ci.yml` has no GHCR login). **The `build-args:`
blocks are the one part currently byte-identical across all four.** The change
deduplicates the only section that has not drifted.

### F5 — The repo already built this boundary, for Windows

Verified inventory: `.github/actions/` contains exactly one composite action
(`clean-runner-disk`), and exactly one workflow uses `workflow_call` —
`windows-image.yml`.

`windows-image.yml:7-27` is a reusable workflow owning the *entire* build —
manifest read, metadata, logins, build, push, test — behind a two-input contract
(`target`, `push`), called from `windows.yml:19` and `release.yml:131`.

**The Linux path is the only build path without that boundary.** The change lands
in `setEnvironmentVariables.js` because it is the only file four unrelated
workflows already touch — a shared *file*, not a shared *boundary*.

### F6 — The Windows exclusion is incidental at the arg layer

`windows-image.yml:123` documents the real constraint: "Buildx is unsupported for
Windows containers." That is genuine for the *driver*. But the build-arg *shape*
is not constrained by it — `windows-image.yml:137-146` builds a PowerShell array,
and a newline-separated string splits into one in a single line, an idiom the
file already uses at `:131-132` for tags.

By writing the exclusion as a normative boundary (`spec.md:70-73`), the change
**entrenches** the fork rather than noting it as deferred.

### F7 — The seam that actually caused the staleness is untouched

| Seam | Contract? |
|---|---|
| producers → `version.json` | **Yes** — `cue vet` at `update-version.yml:385` |
| `version.json` → `test/android.yml` | **Yes** — `update_test.sh` + `build.yml:409-416` |
| `version.json` → docs | **Yes** — `docs/examples.cue:7` |
| `version.json` → emitter | **No** — 11 hardcoded paths; a rename yields `undefined` |
| emitter → `build-args:` | **No** — hand-typed in 4 places |
| **`build-args:` → Dockerfile `ARG`** | **No** — nothing cross-checks these |
| `version.json` → `docker-compose.yml` | **No** — and already drifted |

Nothing validates the passed set against the declared set. **That is the seam
whose absence let `android.java.version` sit unwired** — the very defect the
proposal cites as motivation. The change does not close it.

Also: `design.md:88`'s "cannot fail silently" claim is false for the `web` stage
(`android.Dockerfile:225`), which declares none of these args, as
`build.yml:156-157` itself notes.

### F8 — Live drift the proposal does not count

Verified, and unrelated to CI:

- `docker-compose.yml:24-30` lists six android args but **omits
  `android_java_version`** added by PR #537.
- `.env.example:1-7` pins `FLUTTER_VERSION=3.7.7` (manifest: `3.44.9`),
  `ANDROID_BUILD_TOOLS_VERSION=30.0.3` (manifest: `36.0.0`).
- `android.gradle.version` (`config/version.json:16-18`) has **zero consumers**
  repo-wide — written by `updateAndroidVersions.gradle.kts`, constrained by
  `config/schema.cue:47`, read by nothing.

The proposal says "five file edits"; it is six once `docker-compose.yml` counts —
and that sixth is the one already wrong.

## Options

| Approach | Pros | Cons |
|---|---|---|
| **A. Ship as written** | Small; revertable in 3 steps | Motivation is stale (F1); arms `GIT_VERSION` (F2); dedups the 16% that hasn't drifted (F4); entrenches Windows fork (F6); `tasks.md:4`↔`:7` contradiction unresolved |
| **B. `linux-image.yml` reusable workflow** | Removes ~135 duplicated lines vs ~21; exact in-repo precedent (F5); `git_version` structurally impossible to leak; fixes the drifted blocks too | Larger diff; needs `workflow_call` outputs for `test-image`/`scan-image`; fork branching becomes an input |
| **C. Close the ARG↔build-arg seam only** | Directly prevents the class of defect that motivated the change (F7); tiny; orthogonal | Leaves all duplication in place |

```
   OPTION A                     OPTION B
   ┌──────────────┐             ┌──────────────────┐
   │ 4 × build-   │             │ linux-image.yml  │
   │ args blocks  │             │ (whole build     │
   │      ↓       │             │  step, 1 copy)   │
   │ 4 × BUILD_   │             └────────┬─────────┘
   │ ARGS ref     │                      │
   └──────────────┘             ┌────────┴────────┐
   ~45-line step                ▼        ▼        ▼
   still ×4                  build     ci     release
                             (thin callers, typed inputs)
```

## Recommendation

**Decided: Option B + Option C.** The change was repointed to `linux-image.yml`
on 2026-08-09; `proposal.md`, `design.md`, `tasks.md`, and the spec (now
capability `linux-image-build-boundary`) were rewritten accordingly, and the
superseded `manifest-build-arg-wiring` spec directory was removed. Option C (F7)
is tracked as issue #539 rather than folded in, because the seam check is
correct independently of this change's shape. F8 is folded into
`../loud-deb-pin-resolution/research.md` F10, where the original five-edit
observation lives.

```
  BEFORE                              AFTER
  ┌────────────────┐                  ┌────────────────┐
  │ version.json   │                  │ version.json   │
  └───────┬────────┘                  └───────┬────────┘
          ▼                                   ▼
  ┌────────────────┐                  ┌────────────────┐
  │ emitter → 12   │                  │ emitter (typed │
  │ vars, flat env │                  │ per-target)    │
  └───────┬────────┘                  └───────┬────────┘
          │                                   ▼
  ┌───────┴────────┐                  ┌────────────────┐
  ▼   ▼   ▼   ▼    ▼                  │ linux-image.yml│◀── one
 4× full build step                   │  (build-args   │    home
 (~45 dup lines ea.)                  │   live here)   │
          │                           └───────┬────────┘
          ▼                             ┌─────┴─────┐
   android.Dockerfile                   ▼     ▼     ▼
   (no seam contract)                build  ci  release
                                          │
                                          ▼
                                  android.Dockerfile
                                  ▲ ARG↔build-arg check
```

Rationale:

1. **The premise is gone (F1).** The defect was fixed without this change. What
   remains is a duplication argument — and duplication is better answered by the
   boundary the repo already proved on Windows (F5) than by a new indirection.
2. **As written it introduces risk (F2).** The `tasks.md:4`↔`:7` contradiction
   plus warn-don't-fail semantics means a partition error is silent. Option B
   removes the risk by construction: a Linux-only workflow never names
   `git_version`.
3. **It targets the wrong 16% (F4).** The build-arg blocks are byte-identical;
   the login/cache/metadata blocks have drifted.
4. **Keep two things from the current change**: fail-loud on an unresolvable
   manifest path (`tasks.md:10`) and logging the resolved args
   (`design.md:93`). Both are good regardless of shape.

If Option B is judged too large for one sitting, the honest minimum for Option A
is: correct the stale premises and counts, add an explicit **target column**
(`android` | `windows` | `both`) so the partition is specified rather than
implied, and drop the normative Windows exclusion to a deferral. The target
column is also the first column of the provenance model (F3), so it does not
foreclose the larger fix.

Separately worth filing (F8, not blocking): `docker-compose.yml` missing
`android_java_version`, stale `.env.example`, and dead `android.gradle.version`.

## Open Questions

None blocking. Two items were resolved by investigation rather than assumption:
whether unmatched build-args fail (they warn — searched Docker build-checks docs
and buildx issues) and whether reusable workflows can feed downstream jobs (yes,
via `workflow_call` outputs — fetched GitHub docs).

## Next Steps

Artifacts are repointed and validate clean (24 tasks). The stale premises are
corrected: the proposal now records the `android.java.version` wiring as a
correction of record, and every count says seven.

Ready for `/opsx:apply`. The main implementation risk is task 1.5 —
`workflow_call` outputs under `build.yml`'s target matrix, where the caller-side
value is that of the last successful run that set one.

Sources: [Docker build checks](https://docs.docker.com/reference/build-checks/invalid-default-arg-in-from/),
[buildx check tuning](https://github.com/docker/buildx/issues/2704),
[GitHub reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).
