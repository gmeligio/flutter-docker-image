## 1. Route the changelog through a PR (prepare-release.yml)

- [ ] 1.1 In `update-changelog`, replace the `grafana/github-api-commit-action` direct push (`prepare-release.yml:71-76`) with `peter-evans/create-pull-request@v7` using the App token and `sign-commits: true`, on a branch like `release/changelog-${{ env.FLUTTER_VERSION }}`, title/body describing the changelog bump.
- [ ] 1.2 Enable auto-merge on that PR (`gh pr merge --auto --squash <pr>` with the App token), so it merges once required checks pass.
- [ ] 1.3 Decouple `create-tag` from the in-run `needs: update-changelog` edge per design D1a: create the tag from the **merged** `main` commit (the existing `push: { branches: [main], paths: [config/version.json] }` trigger re-enters after merge; `createGitTag.js` is idempotent so re-entry is safe). Verify the tag points at the merged SHA that includes `changelog.md`.

## 2. Route docs through a PR (update-docs.yml)

- [ ] 2.1 Replace the `github-api-commit-action` direct push (`update-docs.yml:50-56`) with `peter-evans/create-pull-request@v7` (App token, `sign-commits: true`) on a branch like `docs/regenerate-${{ github.sha }}`.
- [ ] 2.2 Enable auto-merge on the docs PR (`gh pr merge --auto --squash`). Keep `success-if-no-changes` behavior: if the build produced no diff, open no PR.

## 3. Enable Renovate auto-merge (renovate.json)

- [ ] 3.1 Add `"automerge": true` and `"platformAutomerge": true` to `.github/renovate.json`. Confirm ≥1 required status check exists (5 do) so `platformAutomerge` cannot merge a failing PR.

## 4. Remove the ruleset bypass actor (external)

- [ ] 4.1 In the **external** ruleset code, remove the `bypass_actors` entry (`actor_id: 987256`). Do this only **after** tasks 1–3 are merged and a release has completed through the PR flow (task 5.1). Sequencing per design D4 avoids a "no bypass + still pushing directly" gap.

## 5. Verify

- [ ] 5.1 Dispatch `prepare-release.yml` (`workflow_dispatch`) or wait for a real version bump. Confirm: a changelog PR opens (no direct push), required checks run on it, auto-merge merges it, the tag job then creates `refs/tags/X.Y.Z` at the merged SHA, and `release.yml` fires on the tag push.
- [ ] 5.2 Trigger `update-docs.yml`; confirm regenerated docs land via an auto-merged PR (or no PR when there is no diff).
- [ ] 5.3 Confirm the next Renovate PR auto-merges on green; confirm a PR with a failing required check stays open and is NOT merged.
- [ ] 5.4 After bypass removal (4.1), confirm a residual direct-push attempt to `main` is rejected by the ruleset, and a subsequent release still completes through the PR flow.
