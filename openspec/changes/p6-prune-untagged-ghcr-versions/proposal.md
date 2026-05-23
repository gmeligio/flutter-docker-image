## Why

`ghcr.io/<owner>/flutter-android` carries 836 untagged manifest versions out of 886 total (~94%). They accumulate every time a `pr-N` tag moves on re-run, a release re-tag detaches the prior manifest, or a buildcache layer is replaced. p4 (cleanup-pr-image-tags) only deletes the tagged handoff on PR close/branch delete — it does not address the orphan manifests left behind. Without a separate sweep, GHCR storage debt grows monotonically per PR re-run, slowing the package UI and accruing storage cost.

## What Changes

- New workflow `.github/workflows/prune_ghcr_untagged.yml` on `schedule:` (cron, weekly) and `workflow_dispatch:` for manual runs.
- Enumerates `gh api /user/packages/container/flutter-android/versions --paginate` and filters to entries where `metadata.container.tags == []` AND `created_at` is older than a retention window (default 7 days).
- Deletes each match via `gh api -X DELETE /user/packages/container/flutter-android/versions/<id>`, reusing the path/permission p4 already validated (package → repo Actions Access role is Admin).
- Dry-run mode (default on `workflow_dispatch` with input `dry_run: true`) prints the candidate list without deleting; the scheduled run executes the delete.
- Idempotent: a missing version is a no-op success.

## Capabilities

### New Capabilities

- `ci-image-orphan-pruning`: defines when untagged manifest versions on `ghcr.io/<owner>/flutter-android` SHALL be pruned, what tags SHALL be preserved, the retention-window contract that protects in-flight `docker pull` consumers, and the safety guarantees that prevent deletion of tagged versions.

### Modified Capabilities

_None._ Distinct from `ci-image-tag-lifecycle` (p4): that capability owns *tagged* handoff cleanup on PR-close / branch-delete events; this one owns *untagged* manifest pruning on a schedule.

## Impact

- **Affected files**: new `.github/workflows/prune_ghcr_untagged.yml`. No edits to existing workflows.
- **Behavioral change**: GHCR version count on `flutter-android` drops from ~886 to ~50 on first scheduled run; thereafter holds steady near the count of currently-tagged versions plus orphans from the past 7 days.
- **Risk**: a buggy filter could delete a tagged version (release, `pr-N`, `branch-X`, or `buildcache`). Mitigation: the filter SHALL be a positive assertion (`tags == []`) AND a date check; the workflow logs every candidate id + tag list before deleting; a maintainer reviewing the log can spot a wrong delete. Defense in depth: the spec scenarios assert the tagged-protection invariant explicitly.
- **Risk**: deleting an orphan manifest that is still part of a manifest list (multi-platform release) would break the parent. Mitigation: this repo ships single-platform images today; manifest-list semantics are out of scope. If multi-platform is added later (e.g., arm64), the workflow MUST be extended to walk the manifest tree before pruning.
- **Depends on**: p4-cleanup-pr-image-tags is not a hard dependency, but p4 reduces the rate of new orphan creation (each `pr-N` deletion also untags one manifest, growing the orphan pool by one). Land p4 first to converge the steady-state count faster.
- **Out of scope**: Windows package (`flutter-windows-server` or similar — separate release flow), cross-package pruning, deleting tagged-but-superseded release versions (those have their own lifecycle).
