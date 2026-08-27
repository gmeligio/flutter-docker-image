# Design: sync published image descriptions from a declared image set

## Context

The repo publishes four images — `flutter-android`, `flutter-web`,
`flutter-linux` (stages of `android.Dockerfile`, ubuntu runners) and
`flutter-windows` (`windows.Dockerfile`, `windows-2025`) — to Docker Hub, GHCR,
and Quay. Which images exist is stated by hand in ~12 places; only
`docs/build.mjs:44` treats the set as data, and it is in the documentation
layer.

`config/version.json` is the declared single source of truth but models tool
*versions* only: `config/schema.cue`'s root definition is `#Version` and every
key under it is a version. `script/setEnvironmentVariables.js:88-90` resolves
one `IMAGE_REPOSITORY_NAME` a caller already supplies; nothing can answer "which
images does this release publish?"

Two constraints shape the solution:

- **Membership differs per concern.** `flutter-windows` is published and
  verified, but is not Scout-scanned (Scout does not support Windows images) and
  pushes no PR handoff tag (`windows.yml:20` builds with `push: false`). A flat
  list of names cannot express this.
- **`release.yml` never runs on `pull_request`** — it triggers on `push: tags`
  and `workflow_dispatch` (`release.yml:3-7`). The description sync cannot be
  verified pre-merge by any normal check.

The full research, including the live Docker Hub state and the ~12 enumerations,
is in `research.md`.

## Goals / Non-Goals

**Goals:**

- `flutter-windows` gets a Docker Hub description, keeping its tailored short
  description.
- The published image set is declared once, machine-readable, and schema-guarded.
- Every workflow matrix that enumerates images derives from that declaration.
- Exclusions carry a stated reason instead of being unmarked absences.
- Close #521 and #544 in one change.

**Non-Goals:**

- **Per-image Docker Hub descriptions.** Today one shared `readme.md` goes to
  all repos, so each image's page describes all four. Real defect, separate
  concern — its own issue.
- **Enabling Scout for Windows.** Docker Scout does not support Windows images;
  this change records that, it does not work around it.
- **Restructuring `release.yml`.** It is a catch-all spanning build, verify,
  describe, scan, and GitHub-release, and three of five downstream jobs hang off
  `release-linux` as an ordering anchor rather than a real dependency. Only the
  `update-description` edge is corrected here, because it is load-bearing for
  this change. The rest is noted in `research.md`, not attempted.
- **Changing any published image, tag, or artifact.** No image contents change.

## Decisions

### 1. A new `config/images.json`, not an `images` key in `version.json`

`version.json` is a version manifest — `schema.cue`'s root is `#Version` and
every existing key is a tool version. The image set is a different kind of fact
with a different change cadence: a Flutter bump (`update-version.yml`, monthly)
must not touch the same file as an image-set change (rare, structural).

*Alternative considered:* extend `version.json`. Cheaper wiring —
`docs/build.mjs:16` already reads it and `update-docs.yml:18` already watches
it. Rejected: conflating identity with versions puts the automated monthly
version-bump PR and structural image changes in the same file, and `#Version` is
a closed definition whose meaning would blur.

*Cost accepted:* `docs/build.mjs` needs a second `readFileSync`, and
`config/images.json` **must** be added to `update-docs.yml:18`'s `paths:` filter
— otherwise an image-set change regenerates no docs and drift goes undetected.

### 2. A discriminated `dockerfile` field, not a bare disjunction

The schema must require `target` and `testConfig` for images built from
`android.Dockerfile` while allowing Windows to omit both. A plain disjunction
(`#LinuxImage | #WindowsImage`) does not work — verified against CUE:

```
images.1: incomplete value {...} | {...}
images.0.target: field is required but not present
```

CUE cannot choose a branch, so it reports both. A discriminator field resolves
it. Verified working:

```cue
#Image: {
	name!:             string
	shortDescription!: string
	scout!:            bool
	prTag!:            bool
	dockerfile!:       "android" | "windows"

	if dockerfile == "android" {
		target!:     string
		testConfig!: string
	}
	if dockerfile == "windows" {
		scout: false   // Docker Scout does not support Windows images
		prTag: false   // windows.yml builds with push: false
	}
}
```

This makes the two exclusions **schema-enforced rather than conventional**: a
future edit setting `scout: true` on a Windows image fails validation with
`conflicting values false and true`, not silently at runtime. That is the
mechanism the change is really buying — the original defect was an unmarked
absence that no tool could catch.

*Alternative considered:* keep all fields optional and validate in the workflow.
Rejected — it moves the guard from `cue vet` (which runs before any build, per
`validate-version-manifest`'s stated purpose) to a job that fails minutes later.

### 3. Matrices come from a `setup` job emitting `fromJSON`

GitHub Actions cannot read a file into `strategy.matrix` directly. A `setup` job
reads the manifest, filters with `jq`, and emits the list as a job output that
downstream jobs expand with `fromJSON`. This pattern already exists at
`build.yml:22-27`.

Each consumer filters for what it needs (all verified against the prototype):

| Consumer | Filter |
| --- | --- |
| `update-description` | all images, with `name` + `shortDescription` |
| `record-image` | `select(.scout)` → three |
| `build.yml` build/release build | `select(.dockerfile == "android")` |
| `build.yml` test | `select(.testConfig)` |
| `cleanup-pr-image` | `select(.prTag)` |

*Alternative considered:* a composite action per concern, as with
`build-linux-image`. Rejected for the matrix itself — a composite action runs
*inside* a job and cannot produce a job's matrix. The composite pattern remains
right for step-level work; this is job-level fan-out.

### 4. `shortDescription` becomes per-image data

`peter-evans/dockerhub-description` PATCHes both fields, sending `description`
whenever non-empty (`src/dockerhub-helper.ts`):

```ts
const body = { full_description: fullDescription }
if (description) { body['description'] = description }
```

`release.yml:224` currently passes `github.event.repository.description`, always
non-empty. `flutter-windows` carries a hand-set
`"Docker images for Flutter CI in Windows platform"`, so adding it to the matrix
naively would **overwrite the one field where the Windows page is better than
the others.** Sourcing `shortDescription` per image from the manifest avoids the
regression and removes a hidden dependency on the GitHub repo description. Cap
is 100 bytes, truncated with a warning (`src/main.ts:7`).

### 5. `update-description` depends on both release jobs

`needs: release-linux` → `needs: [release-linux, release-windows]`
(`release.yml:181`), matching `verify-published:142`. Without it the Windows leg
could sync a description for an image whose build failed. `release.yml:137-141`
already documents this class of coupling as the reason a job drifted before.

`if: !cancelled()` is retained, so one image's failure does not skip the others'
sync.

### 6. Scout exclusion is recorded, not removed

`record-image` continues to exclude `flutter-windows` — but via `scout: false`
with a stated reason, schema-pinned per decision 2. This **upholds** the
archived trade-off at
`openspec/changes/archive/2026-05-20-p2-release-windows-image/design.md:67`
while **reversing** the adjacent description trade-off (`:66`), whose stated
premise — "users discover the Windows variant via the GitHub README" — expired
when the README made Windows first-class.

## Risks / Trade-offs

- **[Risk] `build.yml` is in the diff.** It is the PR-critical path and the
  largest workflow (488 lines). A defect in the release matrices surfaces on the
  next tag; one in `build.yml` breaks every PR immediately. → **Mitigation:**
  `build.yml` runs on `pull_request`, so the PR exercises itself. Confirm the
  build, test, and scan legs each still enumerate exactly three images on the
  PR's own run before merging.

- **[Risk] The description sync cannot be verified pre-merge.** `release.yml`
  runs only on `push: tags` and `workflow_dispatch`. → **Mitigation:** the
  matrix expansion *is* observable pre-merge from the setup job's output and the
  rendered job names. The sync itself is verified post-merge against the Docker
  Hub API (acceptance criteria in #521). The action is idempotent, so a failed
  sync is retried by the next tag with no cleanup.

- **[Risk] A malformed `images.json` breaks every image matrix at once.**
  Previously a bad edit broke one hand-written matrix. → **Mitigation:** `cue
  vet` runs in `validate-version-manifest` before any build step, which is
  precisely that action's stated purpose ("otherwise a bad value fails minutes
  later against a Dockerfile ARG"). An empty or unparseable matrix fails the
  setup job, before any image is built or pushed.

- **[Risk] Docs drift becomes undetectable if the `paths:` filter is missed.**
  `update-docs.yml:18` gates regeneration on `config/version.json`; an
  image-set-only change would not trigger it. → **Mitigation:** adding
  `config/images.json` to that filter is an explicit task, not an incidental
  edit.

- **[Trade-off] `dockerfile` is a new concept in the manifest.** It names the
  build source, which no existing config field does. Accepted: it is the honest
  discriminator (the real split is which Dockerfile an image comes from), and it
  gives the naming collision noted in `research.md` — `linux` meaning both host
  OS and Flutter target — a place to be stated rather than inferred from prose.

- **[Trade-off] Six workflow matrices change in one PR.** Larger review surface
  than the one-line fix in #521. Accepted deliberately: the one-line fix leaves
  the mechanism that produced the bug, and the identical defect is already open
  as #544 having already cost 32 orphaned tags.

## Migration Plan

No data migration; the manifest is new and additive.

1. Add `config/images.json` + `#Images` in `schema.cue`; extend
   `validate-version-manifest` to `cue vet` it. Verifiable standalone.
2. Convert matrices one workflow at a time, `build.yml` last (highest blast
   radius, fully exercised by the PR itself).
3. Point `docs/build.mjs` at the manifest; add the `paths:` filter entry.
   `mise run docs` must produce a byte-identical `readme.md` — the generated
   output is unchanged by this work, so any diff is a defect.

**Rollback:** revert the PR. The manifest is read-only input to matrix
construction; nothing persists to a registry, and no published image or tag is
touched. A partial rollback (reverting one workflow to its literal matrix) is
also safe, since the manifest and the literals describe the same set.

## Automated Test Strategy

**Pre-merge (the level that matters here):**

- `cue vet config/schema.cue -d '#Images' config/images.json` via
  `validate-version-manifest` — runs in every job that reads a manifest. The
  negative cases are the point and were verified against CUE while writing this
  design: a Linux image missing `target`/`testConfig` fails with `field is
  required but not present`; a Windows image asserting `scout: true` fails with
  `conflicting values false and true`.
- `build.yml` on this PR is the real test of the matrix conversion: build, test,
  and scan legs must each enumerate exactly three images, and each leg's rendered
  name must match today's. A structural regression shows as a missing or extra
  matrix leg, which is visible in the checks list without reading logs.
- `update-docs.yml` fails if `readme.md` drifts from a fresh `mise run docs`.
  Since this change alters the generator's *input source* but not its *output*,
  the expected diff is empty — a non-empty diff is a defect.

**Post-merge:** the next tag exercises `release.yml`. Acceptance per #521:

```bash
curl -s https://hub.docker.com/v2/repositories/gmeligio/flutter-windows/ | jq .full_description   # non-null
curl -s https://hub.docker.com/v2/repositories/gmeligio/flutter-windows/ | jq .description        # "...in Windows platform", unchanged
```

`flutter-linux` — currently also null, having shipped after the last tag — is
expected to populate on that same run.

**No new test infrastructure.** The change is YAML, JSON, CUE, and one JS
generator; `cue vet` and the existing docs-drift check are the guards.

## Observability

- **Schema failure** surfaces as a failed `validate-version-manifest` step
  naming the offending field and JSON path — before any build starts, which is
  that action's documented reason for existing.
- **Matrix construction failure** surfaces as a failed `setup` job. Downstream
  jobs then report as skipped rather than silently running an empty matrix. The
  emitted matrix should be logged so a wrong-but-valid filter (e.g. three legs
  where four are expected) is diagnosable from the run alone.
- **Silent-failure path — the one that matters.** An empty matrix expands to
  zero legs and reports **green**. That is exactly the shape of the original
  bug: `update-description` has been passing for months while never touching
  `flutter-windows`. Guard it by asserting non-empty in the setup job and
  failing loudly if any filter yields nothing.
- **Sync failure** surfaces as a failed `update-description` leg named for its
  image (`Update Docker Hub description (flutter-windows)`). The action calls
  `core.setFailed` on a non-OK PATCH; a short-description truncation emits
  `core.warning` rather than failing.
- **Not observable in CI:** whether the Docker Hub page *renders* correctly.
  Only the API's `full_description` being non-null is machine-checkable.

## Open Questions

None blocking. Two items deliberately deferred, each to its own issue: per-image
Docker Hub descriptions (Non-Goals), and the `release.yml` structural cleanup
that `research.md` describes — three of five downstream jobs hanging off
`release-linux` as an ordering anchor, including `create-github-release`, whose
own comment (`release.yml:286-288`) admits the edge is wrong.
