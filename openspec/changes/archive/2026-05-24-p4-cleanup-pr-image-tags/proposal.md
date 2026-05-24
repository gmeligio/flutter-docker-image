## Why

p2 introduces `pr-<N>` and `branch-<branch>` tags on `ghcr.io/<owner>/flutter-android` so downstream jobs (p3) can pull the just-built image. These tags are useful only during the life of the PR — once the PR closes (merged or not), they are dead weight on GHCR. Without a cleanup, the registry accumulates one stale tag per PR ever opened.

`workflow_dispatch` tags (`branch-<branch>`) are stale as soon as the branch is deleted. Branches can be deleted with no PR ever closing.

This change adds a small workflow that deletes the right tag when the PR closes or the branch is deleted, keeping the registry tidy.

## What Changes

- New workflow `.github/workflows/cleanup_pr_image.yml` triggered on:
  - `pull_request: { types: [closed] }` — deletes `pr-<N>` when the PR closes (merged or not).
  - `delete:` (with `ref_type == 'branch'`) — deletes `branch-<branch-with-/-→--->` when a branch is deleted.
- Uses `gh api -X DELETE /user/packages/container/flutter-android/versions/<id>` after resolving the version id from the tag.
- Runs on `ubuntu-24.04`, single job, < 30 s wall-clock.
- Permissions: `packages: write` only.
- Idempotent: a missing tag is a no-op success, not a failure.
- Fork PRs never produced a tag (p2 uses the artifact path for them); the cleanup workflow detects "tag not found" and exits 0.

## Capabilities

### New Capabilities

- `ci-image-tag-lifecycle`: defines when temporary handoff tags on `ghcr.io/<owner>/flutter-android` SHALL be deleted, what triggers cleanup, and the idempotency contract for repeated or fork-PR runs.

### Modified Capabilities

_None._

## Impact

- **Affected files**: new `.github/workflows/cleanup_pr_image.yml`. No edits to existing workflows.
- **Behavioral change**: GHCR no longer accumulates `pr-*` and `branch-*` tags on `flutter-android`. The release tags (`<flutter-version>`) are untouched — the cleanup matches only the documented temporary-tag patterns.
- **Risk**: a buggy match pattern could delete the release tag. Mitigation: the workflow is gated to delete only tags matching `^pr-\d+$` or `^branch-.+$` literal-regex; the spec scenario asserts this explicitly. Defense in depth: the workflow logs the version-id and tag name before delete; a maintainer reviewing the workflow log can spot a wrong delete.
- **Depends on**: p2 (or co-merged). Has no value without the tags p2 creates.
- **Permission model**: Relies on the package's *Manage Actions access* granting `gmeligio/flutter-docker-image` the **Admin** role — already configured (verified 2026-05-23). With Admin, the workflow `GITHUB_TOKEN` with `packages: write` can DELETE versions; without it, the same call would 403. No PAT needed.
- **Out of scope**: cleanup of fork-PR artifacts (p2 already sets `retention-days: 1`, GitHub auto-deletes). Cleanup of the `buildcache` tag (p1's `mode=max` overwrites in place; no accumulation).
