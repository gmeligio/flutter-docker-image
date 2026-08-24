## Why

PR builds push a `pr-<N>` handoff tag for **both** Linux images:
`build.yml`'s matrix covers `flutter-android` and `flutter-web` (`:48-55`), and
the GHCR ref is built from `matrix.name` (`:64`, `:132-138`). Cleanup deletes
one of them. `cleanup-pr-image.yml:26` hardcodes
`PACKAGE_NAME: flutter-android`, and that single name is what the two API calls
query (`:66`, `:82`).

So every closed PR leaves a `flutter-web:pr-<N>` tag behind. Counted against
GHCR on 2026-08-12, with PR #533 the only open PR:

| Package | Total tags | Handoff tags | Orphans |
|---|---|---|---|
| `flutter-android` | 160 | 4 | **3** — `pr-454`, `pr-455`, `pr-456` |
| `flutter-web` | 41 | 33 | **32** — `pr-489` through `pr-543` |
| `flutter-windows` | 8 | 0 | none — pushes nothing on a PR |

Each orphan is a full image index carrying SBOM and provenance attestations
(`build.yml:151-155`), not a bare tag. The `flutter-web` count grows by one per
PR.

`branch-<ref>` handoff tags have the same exposure. `build.yml` also triggers on
`workflow_dispatch` (`:5`), and the handoff computation is a plain if/else on
whether the event is a `pull_request` (`:118-125`): a dispatch falls to the
`else` and pushes `branch-<ref>` for both images, gated only on `is_fork`
(`:145`), which a dispatch always satisfies. None exist on GHCR today — nobody
has dispatched `build.yml` from a branch recently — but the producer is live and
already matrixed, so the same single-image cleanup gap applies to it.

`flutter-android`'s remaining 156 tags are not in scope and must survive the
sweep. Besides releases and `buildcache`, 59 of them are in two legacy shapes
that predate the `pr-<N>` convention and appear on no other package:
`<semver>-<sha>` (28, e.g. `3.10.1-65320358`, with both short and full SHAs) and
bare `<sha>` (31, e.g. `b3ea316206313fdd7ac4aacd95fb95c3e2786cf5`), all in the
3.7.x–3.10.x range. Nothing in the repo produces them today. The handoff-tag
regex already excludes them, so the workflow cannot reach them — but the sweep
runs outside the workflow, which is what makes applying the same guard
deliberately (task 2.5) load-bearing rather than ceremonial. They are also
standalone: no GHCR version carries more than one tag, so none of them is an
alias of a live release tag.

The three `flutter-android` orphans are a second, smaller defect with a
different cause: that image *is* covered by the workflow, so these are residue
from runs where deletion never happened — the tags predate the current cleanup
workflow, or their runs failed. They are not evidence the matrix is wrong.
Both sets are swept together because the sweep is one operation and leaving a
known orphan behind would make the post-sweep check meaningless.

The spec has the same defect: `ci-image-tag-lifecycle`'s Purpose and both
deletion requirements are scoped to `ghcr.io/<owner>/flutter-android`
(`spec.md:5,11,17,43`). The workflow matches its spec — the spec was written
when `flutter-android` was the only image and never revisited when
`flutter-web` was added.

Relevance gate: this changes what a maintainer finds when auditing GHCR
storage — one tag per open PR, as the capability already promises, rather than
one per ever-opened PR on an image nobody was cleaning.

## What Changes

- `cleanup-pr-image.yml` iterates the images that produce handoff tags instead
  of naming one, with `fail-fast: false` so one image's failure does not skip
  another's.
- The 35 existing orphans are swept once — 32 on `flutter-web`, 3 on
  `flutter-android`. The workflow fires only on `pull_request: closed` and
  `delete`, so it will never revisit tags for PRs that are already closed.
- `ci-image-tag-lifecycle` is de-scoped from `flutter-android` — its two
  deletion requirements via the delta, and its Purpose line directly (see
  Impact).

Explicitly **not** in scope:

- Declaring the published image set in a config file. The image list here is
  short, local, and about which images produce *handoff tags* — a narrower
  question than which images are published. If a declaration lands later this
  workflow is a natural consumer, but it is not a prerequisite.
- `flutter-windows`, which produces no handoff tags: `windows.yml` calls
  `windows-image.yml` with `push: false` (`windows.yml:19-22`), so a PR
  builds it without pushing anything to delete.
- The two image-agnostic requirements in the capability, *Cleanup never
  targets a non-handoff tag* (`spec.md:47`) and *Cleanup workflow runs with
  minimum privilege* (`:68`). Both already hold for any image.
- `branch-main`. Dispatching `build.yml` from the default branch pushes it, and
  cleanup can never reach it: `main` is never deleted, so the `delete` event
  never fires. That is not a leak. Every dispatch overwrites the same tag, so it
  is bounded at one image index per package — the footprint of `buildcache` —
  and it holds the latest `main` build. Unbounded growth is what makes the
  `pr-<N>` case a defect, and this has none. Left in place deliberately.

## Capabilities

### Modified Capabilities

- `ci-image-tag-lifecycle`: its two deletion requirements are de-scoped from
  `ghcr.io/<owner>/flutter-android` to every image that produces handoff tags,
  and gain the guarantee that one image's cleanup failure does not skip
  another's.

## Impact

**Modified**: `.github/workflows/cleanup-pr-image.yml` (matrix over the image
names, `fail-fast: false`); `openspec/specs/ci-image-tag-lifecycle/spec.md` —
its two deletion requirements on archive, via the delta, and its Purpose line
(`:5`) directly in this PR. The split is forced by the tooling: OpenSpec 1.3.1
deltas carry only requirement operations, so a Purpose edit has no delta form
and archive preserves whatever Purpose it finds.

**One-off**: sweep the orphaned `flutter-web` handoff tags. Deletion must
resolve a specific `pr-<N>` tag to a version ID and delete by ID — a
`tags == []` filter would match OCI index children and break parent tags.

**Verification**: after the sweep, each package should carry handoff tags only
for open PRs. The next closed PR should leave neither image with a `pr-<N>`
tag.

**Risk**: the sweep is a destructive registry operation. It is bounded by the
existing tag-regex guard (`:49-52`), which refuses anything that is not
`pr-<N>` or `branch-<ref>` — keeping release tags, `buildcache`, and
`flutter-android`'s 59 legacy `<semver>-<sha>` and bare-`<sha>` tags unreachable.
The one-off sweep runs outside that workflow, so it needs the same guard applied
deliberately rather than inherited.

Deleting by resolved version ID matters for the same reason. `flutter-android`
holds 1061 versions against 160 tags, so roughly 900 are untagged OCI index
children of tagged parents — precisely the population a `tags == []` filter
would select and destroy.
