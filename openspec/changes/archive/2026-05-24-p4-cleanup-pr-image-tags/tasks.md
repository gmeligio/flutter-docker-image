## 1. Add the cleanup workflow

- [x] 1.1 Create `.github/workflows/cleanup_pr_image.yml` with:
  - `on.pull_request.types: [closed]`
  - `on.delete:` (then job-level `if: github.event.ref_type == 'branch'`)
  - `permissions: { packages: write, contents: read }`
  - `concurrency: cleanup-pr-image-${{ github.event.pull_request.number || github.event.ref }}` with `cancel-in-progress: false` (a second close event for the same PR is a no-op).
- [x] 1.2 Compute the target tag in a shell step:
  - `pull_request` event → `pr-${{ github.event.pull_request.number }}`
  - `delete` event → `branch-${{ github.event.ref }}` with `/` → `-`
  - Assert the tag matches `^pr-[0-9]+$` or `^branch-[A-Za-z0-9._-]+$`. Refuse to proceed if it doesn't — satisfies spec scenario "Cleanup never targets a non-handoff tag".
- [x] 1.3 Resolve the GHCR package version id: `gh api /user/packages/container/flutter-android/versions --paginate --jq '.[] | select(.metadata.container.tags[]? == "<tag>") | .id'`. The `/user/...` (authenticated-user) endpoint is used because the package is user-owned (`gmeligio`); the workflow's `GITHUB_TOKEN` can resolve and delete via this path because the package → repo Actions Access role is Admin (verified live on 2026-05-23 by deleting version 865726171 / `pr-453`, HTTP 204).
- [x] 1.4 Delete: `gh api -X DELETE /user/packages/container/flutter-android/versions/<id>`. On `404`, log and exit 0 (idempotent — tag already gone, either from a prior cleanup run or from a fork PR that never produced a tag).

## 2. Verify on a real PR before merge

- [ ] 2.1 Open a non-fork PR (so p2 produces a `pr-N` tag), close it, confirm `pr-N` is removed from GHCR within 60 s. Repeat with a merge-close.
- [ ] 2.2 Trigger a `workflow_dispatch` on a feature branch (so p2 produces `branch-<name>`), then delete the branch. Confirm the tag is removed.
- [ ] 2.3 Close a PR that never produced a tag (fork PR — p2 used the artifact path). Confirm the workflow runs, logs "tag not found, nothing to delete", and exits 0.

## 3. Post-merge closure check

- [ ] 3.1 After 5 PRs have closed post-merge, list GHCR tags on `flutter-android` and confirm no `pr-*` or `branch-*` tags exist for closed PRs / deleted branches.
- [ ] 3.2 Confirm the `<flutter-version>` release tags are untouched.
