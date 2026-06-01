## Context

Two workflows currently push directly to `main`, relying on the ruleset's bypass actor:

```
  config/version.json change on main          docs/src/** change on main
            │ (push)                                    │ (push)
            ▼                                           ▼
  prepare-release.yml                          update-docs.yml
   ├─ update-changelog → DIRECT PUSH (changelog.md)  └─ DIRECT PUSH (regenerated docs)
   └─ create-tag (needs: update-changelog)
        → createGitTag.js → refs/tags/X.Y.Z → release.yml (push: tags)
```

The release chain has a subtle coupling: `create-tag` runs after `update-changelog` via a `needs:` edge **within the same workflow run**, and tags the changelog commit's SHA. `release.yml` then fires on the tag push. We must preserve "tag is created only after the changelog content is on `main`" while changing *how* the changelog lands (PR + merge instead of direct push).

The ruleset is managed as code in an external repository; bypass-actor removal happens there, not in this repo.

## Goals / Non-Goals

**Goals:**
- No workflow pushes directly to `main`; changelog and docs land via PRs.
- The release chain (changelog → tag → `release.yml`) still works end to end.
- Renovate and release/docs PRs auto-merge on green required checks.
- The ruleset bypass actor becomes removable (removed externally).

**Non-Goals:**
- In-repo ruleset-as-code, governance docs, auto-approve workflows, `pull_request_target`.
- Raising `required_approving_review_count` above `0`.
- Changing what the required status checks are.

## Decisions

### D1: changelog lands via an auto-merged PR, and tagging moves off the in-run `needs:` edge

`update-changelog` opens a PR with `peter-evans/create-pull-request` (App token, `sign-commits: true`) instead of pushing. Auto-merge is enabled on that PR (`gh pr merge --auto --squash` with the App token, since `create-pull-request` has no native auto-merge input).

The tag must be created from the **merged** changelog commit on `main`, not chained in the same run via `needs:`. Two viable shapes:

- **D1a (chosen): two-pass, same workflow, gated jobs, triggered by both paths.** `prepare-release.yml` triggers on push to `main` for **either** `config/version.json` **or** `changelog.md`. Pass 1 (version.json changed): the `update-changelog` job runs and opens the changelog PR; `create-tag` is skipped. Pass 2 (changelog.md merged to `main`): `update-changelog` is skipped and `create-tag` runs, tagging the merged `main` SHA that now includes the changelog. Each job is gated with an `if:` keyed on which file the push changed (derived from `dorny/paths-filter` or a `git diff` against the before-SHA / the changed-files API). `createGitTag.js` is idempotent (`createGitTag.js:9-19` no-ops if the tag exists), so an accidental re-entry is safe.

  > **Why the trigger is `changelog.md`, not `config/version.json`:** the changelog PR changes `changelog.md`, so merging it only re-enters the workflow if `changelog.md` is in the path filter. A naive "re-enter on version.json" would never fire on the changelog merge and the tag would never be created.

- **D1b (rejected): poll/wait for the PR to merge inside the same run.** Keeps one pass but blocks a runner waiting on merge + checks; fragile and wasteful.

**Why D1a over D1b:** GitHub's model is event-driven; waiting in-run for an async merge is an anti-pattern. Splitting into two passes keyed on the changed file matches how `release.yml` already keys off the tag push, and avoids a blocked runner.

### D2: docs land via an auto-merged PR

`update-docs.yml` mirrors D1's pattern: build docs → `create-pull-request` (App token) → `gh pr merge --auto`. No tag/release coupling, so this is the simpler of the two.

### D3: Renovate auto-merge via platform automerge

Add `"automerge": true` + `"platformAutomerge": true` to `renovate.json`. GitHub performs the merge respecting the ruleset; `required_approving_review_count: 0` means no approval is needed, and the 5 existing required checks satisfy `platformAutomerge`'s "must have ≥1 required check" precondition. No workflow added.

### D4: bypass-actor removal is external and concurrent

The ruleset's `bypass_actors` entry is removed in the external ruleset code as part of the same rollout — **after** the workflow changes are merged and a release has been verified to complete through PRs (so we never have "no bypass + still pushing directly" mid-rollout).

## Automated Test Strategy

The critical path is the release chain end-to-end; it has no unit-testable surface, so verification is operational:

- **Dry-run the changelog PR flow** by dispatching `prepare-release.yml` via `workflow_dispatch` and confirming: a PR opens (not a direct push), required checks run on it, auto-merge merges it, and the tag job then fires and creates `refs/tags/X.Y.Z` pointing at the merged commit.
- **Confirm `release.yml` triggers** off that tag push (it already keys on `push: tags: ['*']`).
- **Renovate**: confirm the next Renovate PR auto-merges on green and a failing-check PR does not (the `platformAutomerge` safety precondition).
- **Negative test**: after bypass removal, confirm any residual direct-push attempt is rejected by the ruleset.

No new test infrastructure; these are CI observations recorded in tasks.

## Observability

- Each workflow logs the PR number it opened and the auto-merge enablement to the run summary, so a failed release is traceable to the step that broke (PR open vs. merge vs. tag).
- `createGitTag.js` already no-ops idempotently; it should log whether it created or skipped the tag so a missing release is diagnosable.
- Failure is **not** silent: if the changelog PR's checks fail, the PR stays open (visible in the PR list) and no tag is created, so `release.yml` simply doesn't run — an absent release is the signal. The risk to guard against is a *silently stuck* PR (open, never merged); the run summary's PR link makes that visible.

## Risks / Trade-offs

- **[Release chain breaks: tag created before changelog is on `main`]** → D1a tags the post-merge `main` SHA, so the changelog is always present first; `createGitTag.js` idempotency makes re-trigger safe.
- **[Mid-rollout gap: bypass removed while a workflow still pushes directly]** → D4 sequences bypass removal *after* a verified PR-based release.
- **[`platformAutomerge` merges a failing PR]** → not reachable (5 required checks present); the renovate change must not remove that precondition.
- **[Extra latency per release/docs update]** → accepted: one CI round-trip and a brief open-PR window, in exchange for no unreviewed writes to `main`.
- **[App-token PR does not trigger required checks]** → not a risk: the App token is distinct from `GITHUB_TOKEN`, so its PRs trigger workflows normally (unlike `GITHUB_TOKEN`-authored PRs).

## Migration Plan

1. Land the `prepare-release.yml`, `update-docs.yml`, `renovate.json` changes via PR.
2. Verify a full release completes through the PR flow (dispatch or next real version bump).
3. Remove the `bypass_actors` entry in the external ruleset code.
4. Confirm a subsequent direct-push attempt is rejected and releases still succeed.

Rollback: restore the `bypass_actors` entry externally and revert the two workflows to the `github-api-commit-action` direct push.

## Open Questions

- **Does `release.yml`'s `push: tags: ['*']` fire when the tag is created via the App token from a non-`prepare-release` event?** Expected yes (App token ≠ `GITHUB_TOKEN`, so tag pushes trigger workflows), but confirm during the verification release before removing the bypass.
