# Sync published image descriptions from a declared image set

## Why

`gmeligio/flutter-windows` has a blank Docker Hub page (issue #521): the
`update-description` job's matrix (`release.yml:189-191`) lists three images and
omits it. The cause is not a typo — the matrix was copy-pasted from the build
matrix (`release.yml:36-41`), which excludes Windows for a legitimate build
reason (different Dockerfile, different runner). **A build fact silently became
a publication policy.**

The same defect is open separately as issue #544, and has already cost real
cleanup: `cleanup-pr-image.yml` named only `flutter-android`, so every closed PR
left a `flutter-web` orphan behind — 32 accumulated before anyone noticed. The
image set is re-spelled by hand in ~12 places and only one of them,
`docs/build.mjs:44`, treats it as data — in the documentation layer, which has
no authority over CI.

Adding one matrix entry fixes today's symptom and leaves the mechanism that
produced it. Declaring the image set once fixes both issues and every future
instance.

## What Changes

- **New `config/images.json`** — the published image set as data, with the
  per-image properties currently scattered across the workflows: `name`,
  `target`, `shortDescription`, `scout`, `testConfig`, `prTag`. Guarded by a new
  `#Images` definition in `config/schema.cue` and validated by the existing
  `validate-version-manifest` composite action.
- **`flutter-windows` gains its Docker Hub description.** It joins
  `update-description`, which now derives its matrix from the manifest.
- **`flutter-windows` keeps its tailored short description**
  (`"Docker images for Flutter CI in Windows platform"`). The action PATCHes
  `description` whenever non-empty, so passing the generic repo description
  would overwrite it. `shortDescription` becomes per-image data.
- **`update-description` depends on both release jobs.** `needs: release-linux`
  → `needs: [release-linux, release-windows]`, so the Windows leg cannot sync a
  description for an image whose build failed.
- **The Scout exclusion becomes explicit, not accidental.** `record-image` keeps
  `flutter-windows` out — Docker Scout does not support Windows images — but now
  as a declared `scout: false` flag with a stated reason, rather than an
  unmarked absence.
- **Six more enumerations retired** against the same manifest: `release.yml`
  build/verify matrices, `build.yml` build/test/scan matrices (`:52-57`,
  `:215-220`, `:290-292`), and `cleanup-pr-image.yml:33-35`. Both `build.yml`
  comments already claim to "Mirror the build matrix" while hand-copying it.
- **`docs/build.mjs:44`** reads the manifest instead of its own literal, and
  `update-docs.yml:18` adds `config/images.json` to its `paths:` filter so docs
  drift stays detected.
- Closes #521 and #544.

Not breaking: no image name, tag, or published artifact changes. The only
externally visible effects are two Docker Hub pages gaining a description.

## Capabilities

### New Capabilities

- `published-image-set`: The declared set of published images and its per-image
  properties — what the manifest holds, what guards it, and the rule that every
  workflow enumerating images derives its matrix from it rather than restating
  the list. Covers per-concern membership (an image may be published but not
  Scout-scanned, or built on PRs but not push a handoff tag) and requires each
  exclusion to carry a reason.
- `docker-hub-description-sync`: The behavior of publishing a description to
  each image's Docker Hub repository — which images receive one, when it runs
  relative to the release jobs, and that a per-image short description is
  preserved rather than overwritten by a repository-wide default. This has no
  spec home today; it exists only as one sentence inside a docs-codegen spec.

### Modified Capabilities

- `generated-docs-and-examples`: The requirement at `spec.md:31` enumerates
  three images (`flutter-android`, `flutter-web`, `flutter-windows`) while the
  generator produces four, and its scenario is titled "All three images are
  presented from the manifest" (`:51`) — a hand-spelled list that drifted inside
  the spec mandating non-drift. Changes to derive coverage from the image set,
  and to move the Docker Hub description sentence (`:5-7`) out to
  `docker-hub-description-sync`, where publication belongs.
- `ci-image-vulnerability-scan`: Gains the requirement that Scout coverage is
  declared per image rather than assumed uniform, recording that Windows images
  are out of scope because Docker Scout does not support them.
- `ci-image-handoff`: Hardcodes `flutter-android` in the outputs that produce PR
  handoff tags (`spec.md:13,15,26,27`) while `web-image-testing/spec.md:52`
  already asserts `flutter-web` handoff tags exist — the two specs contradict
  each other. Generalizes to the set of images declaring `prTag`. This is
  issue #544.
- `ci-image-anonymous-availability`: The requirement text names only
  `flutter-android` and `flutter-windows` (`spec.md:6-8`) though the workflow
  now verifies four images. Its stated invariant — "the set of verified pairs
  SHALL be exactly the set the run published" — is the correct rule and becomes
  a reference to the declared set rather than a prose enumeration.

## Impact

**Relevance gate.** This clears it on the description sync alone: a CI engineer
evaluating `flutter-windows` on Docker Hub currently sees a blank page and no
statement of what the image contains. That is a user-visible defect on the
project's primary discovery surface. The image-set manifest is included in the
same change because the missing description *is* the symptom of the missing
declaration — fixing only the symptom leaves the mechanism that produced it, and
the identical defect is already open as #544.

**Code:**
- New: `config/images.json`, `#Images` in `config/schema.cue`
- Modified: `.github/workflows/release.yml` (4 matrices, 1 `needs:` edge),
  `.github/workflows/build.yml` (3 matrices),
  `.github/workflows/cleanup-pr-image.yml` (1 matrix),
  `.github/workflows/update-docs.yml` (`paths:` filter),
  `.github/actions/validate-version-manifest`, `docs/build.mjs`

**Risk:** `build.yml` is the PR-critical path and the largest workflow (488
lines). A defect in the release matrices surfaces on the next tag; one in
`build.yml` breaks every PR immediately. Mitigated by `build.yml` running on
`pull_request` — the PR exercises itself.

**Verification limit:** `release.yml` does not run on `pull_request`, so the
description sync cannot be verified pre-merge. Confirmed by the Docker Hub API
after the next tag, per the acceptance criteria in #521.

**Reverses a recorded trade-off.**
`openspec/changes/archive/2026-05-20-p2-release-windows-image/design.md:66`
accepted "No Docker Hub description update for the Windows image" on the grounds
that "users discover the Windows variant via the GitHub README." The README now
documents Windows as a first-class platform, so that premise has expired. The
adjacent Scout trade-off (`:67`) is **upheld**, not reversed.
