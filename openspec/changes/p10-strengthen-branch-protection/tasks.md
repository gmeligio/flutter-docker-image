## 1. Generate the changelog in the version-bump PR; collapse prepare-release to tagging

- [x] 1.1 In `update-version.yml`, before the existing `peter-evans/create-pull-request` step (`update-version.yml:520`), add a `git-cliff --tag ${{ env.FLUTTER_VERSION }} --github-repo ${{ github.repository }} --output changelog.md` step so the regenerated changelog is staged into the version-bump PR. (Implements the `# TODO` at `update-version.yml:518`.) Ensure `git-cliff` is available (mise) and the repo is checked out with enough history/tags.
- [x] 1.2 In `prepare-release.yml`, remove the `update-changelog` job and the changelog generation entirely. Keep only a single `create-tag` job triggered by `push` to `main` on `config/version.json` (and `workflow_dispatch`). It reads the version via `setEnvironmentVariables.js` and calls `createGitTag.js`. No `peter-evans/create-pull-request`, no `git-cliff`, no `changelog.md` trigger path, no direct push.
- [x] 1.3 Confirm `release.yml` is unaffected: it regenerates its own changelog from history (`release.yml:301`) and triggers on the tag push, so it needs no committed `changelog.md`.

## 2. Regenerate docs output onto the PR branch (update-docs.yml)

- [x] 2.1 Change `update-docs.yml` trigger from `push: { branches: [main], paths: [docs/src/**] }` to `pull_request: { paths: [docs/src/**] }` (plus `workflow_dispatch`). Top-level `permissions: { contents: write }`. Check out the PR head (`ref: ${{ github.event.pull_request.head.ref }}`, `repository: ${{ github.event.pull_request.head.repo.full_name }}`) so the regenerated output can be committed back to it.
- [x] 2.2 After `pnpm run build`, commit the regenerated outputs onto the PR branch only if there is a diff, using the App token: set git user to the App identity, `git add -A`, `git diff --cached --quiet || (git commit && git push)`. No new action dependency; no auto-merge (the docs change rides in the human/Renovate PR, which merges normally). The no-diff guard prevents a self-trigger loop on `synchronize`. PR branches come only from the maintainer and `renovate[bot]` (same-repo, never forks), so the App token is available.
- [x] 2.3 Fork-gate the job (`if: github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository`), keep top-level `permissions: contents: read` with `contents: write` scoped to the job, and add `update-docs.yml` to the `pr-head-checkout` scoped ignore in `.github/gx.toml` (the `if:` gate makes the 'pwn request' path unreachable; gx can't see it statically). Confirm `gx lint` exits 0.

## 3. Enable Renovate auto-merge (renovate.json)

- [x] 3.1 Add `"automerge": true` and `"platformAutomerge": true` to `.github/renovate.json`. Confirm ≥1 required status check exists (5 do) so `platformAutomerge` cannot merge a failing PR.

## 4. Remove the ruleset bypass actor (external)

- [ ] 4.1 In the **external** ruleset code, remove the `bypass_actors` entry (`actor_id: 987256`). Do this only **after** tasks 1–3 are merged and a release has completed through the PR flow (task 5.1). Sequencing per design D4 avoids a "no bypass + still pushing directly" gap.

## 5. Verify

- [ ] 5.1 Dispatch `update-version.yml` (or wait for a real version bump). Confirm the version-bump PR includes a regenerated `changelog.md`; merge it; confirm `prepare-release.yml` creates `refs/tags/X.Y.Z` from the merged commit (no direct push) and `release.yml` fires on the tag push. Also confirm a `changelog.md`-only edit produces no tag.
- [ ] 5.2 Open a PR editing a `docs/src/**` source file; confirm `update-docs.yml` regenerates the output and commits it onto the same PR branch, and that a no-diff case pushes nothing and does not loop.
- [ ] 5.3 Confirm the next Renovate PR auto-merges on green; confirm a PR with a failing required check stays open and is NOT merged.
- [ ] 5.4 After bypass removal (4.1), confirm a residual direct-push attempt to `main` is rejected by the ruleset, and a subsequent release still completes through the PR flow.
