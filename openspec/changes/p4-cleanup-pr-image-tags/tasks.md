## 1. Add the cleanup workflow

- [ ] 1.1 Create `.github/workflows/cleanup_pr_image.yml` with:
  - `on.pull_request.types: [closed]`
  - `on.delete:` (then job-level `if: github.event.ref_type == 'branch'`)
  - `permissions: { packages: write, contents: read }`
  - `concurrency: cleanup-pr-image-${{ github.event.pull_request.number || github.event.ref }}` with `cancel-in-progress: false` (a second close event for the same PR is a no-op).
- [ ] 1.2 Compute the target tag in a shell step:
  - `pull_request` event → `pr-${{ github.event.pull_request.number }}`
  - `delete` event → `branch-${{ github.event.ref }}` with `/` → `-`
  - Assert the tag matches `^pr-[0-9]+$` or `^branch-[A-Za-z0-9._-]+$`. Refuse to proceed if it doesn't — satisfies spec scenario "Cleanup never targets a non-handoff tag".
- [ ] 1.3 Resolve the GHCR package version id: `gh api /orgs/${{ github.repository_owner }}/packages/container/flutter-android/versions --paginate --jq '.[] | select(.metadata.container.tags[]? == "<tag>") | .id'`. Handle the user-vs-org path: try `/orgs/<owner>/...` first, fall back to `/users/<owner>/...` on 404.
- [ ] 1.4 Delete: `gh api -X DELETE /orgs/${{ github.repository_owner }}/packages/container/flutter-android/versions/<id>` (or user variant). On `404`, log and exit 0 (idempotent).

## 2. Verify on a real PR before merge

- [ ] 2.1 Open a non-fork PR (so p2 produces a `pr-N` tag), close it, confirm `pr-N` is removed from GHCR within 60 s. Repeat with a merge-close.
- [ ] 2.2 Trigger a `workflow_dispatch` on a feature branch (so p2 produces `branch-<name>`), then delete the branch. Confirm the tag is removed.
- [ ] 2.3 Close a PR that never produced a tag (fork PR — p2 used the artifact path). Confirm the workflow runs, logs "tag not found, nothing to delete", and exits 0.
- [ ] 2.4 Manually create a tag matching `^pr-9999$` then close PR #1 (whose tag doesn't exist). Confirm only `pr-1` is targeted (not `pr-9999`) — satisfies spec scenario "Cleanup never targets a non-handoff tag".

## 3. Post-merge closure check

- [ ] 3.1 After 5 PRs have closed post-merge, list GHCR tags on `flutter-android` and confirm no `pr-*` or `branch-*` tags exist for closed PRs / deleted branches.
- [ ] 3.2 Confirm the `<flutter-version>` release tags are untouched.
