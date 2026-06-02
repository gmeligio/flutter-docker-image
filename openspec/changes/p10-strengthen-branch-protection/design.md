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

Key fact established during design: **the committed `changelog.md` is documentation only — nothing reads it.** `release.yml` regenerates its own changelog from git history at release time (`release.yml:301`) for the GitHub Release body, and `ci.yml` ignores `changelog.md` via `paths-ignore`. So there is no ordering requirement that the changelog be committed before the tag — it can be generated in the same PR that bumps `config/version.json`. `config/version.json` is the single source of truth for "is there a release?"; the changelog rides along as documentation.

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

### D1: the changelog is generated in the version-bump PR; `prepare-release.yml` only tags

Because the committed changelog gates nothing (see Context), it does not need to land before the tag. `update-version.yml` — which already computes the new version and opens the version-bump PR — gains a `git-cliff --tag <new-version>` step that regenerates `changelog.md`. `create-pull-request` already stages all changes, so the changelog rides in the same PR as `config/version.json`. `git-cliff --tag` takes the version as an argument and does not require the tag to exist yet, so there is no chicken-and-egg.

`prepare-release.yml` then collapses to a single job: triggered by a push to `main` touching `config/version.json` (the merged version-bump), read the version, create the tag. No changelog generation, no PR, no second pass, no direct push.

Alternatives considered and rejected:

- **D1a (two-pass / changelog-triggered tag):** keep changelog generation in `prepare-release.yml`, open a changelog PR, and tag on its merge. Rejected: this only existed to preserve a "changelog before tag" ordering that does not actually matter (the changelog gates nothing), and it added a `detect` job, a second trigger path (`changelog.md`), and reliance on tag-idempotency to absorb spurious changelog-only triggers. Folding the changelog into the version PR is strictly simpler and removes `changelog.md` from the trigger surface entirely.
- **D1b (poll for merge in-run):** blocks a runner on an async merge. Rejected.

This also implements the existing `# TODO` at `update-version.yml:518` ("Generate changelog for the new flutter version, that will be the new tag").

### D2: docs output — `check` everywhere, `generate` on same-repo PRs

`docs/src/*.mdx` is **source**; `compile.js` generates committed Markdown outputs (`readme.md`, `windows.md`, `contributing.md`, `license.md`). When the source changes, the outputs go stale. Instead of regenerating them in a separate post-merge PR (the old behavior — asymmetric, two PRs, a window where `main` is out of sync), `update-docs.yml` becomes a **`pull_request`** workflow with two jobs.

Why two jobs rather than one with internal branching: pushing a generated commit **back onto a fork's branch is structurally impossible** from CI — GitHub gives fork-PR runs a read-only token and no secrets, and `pull_request_target`'s token cannot write to someone else's fork. So auto-regeneration can only ever work for same-repo PRs. Forks need the *other* half — a failure that tells the contributor what to run. Splitting these into `check` (safe everywhere) and `generate` (privileged, same-repo only) keeps the always-run required check completely free of secrets and write scope, so it has zero pwn-request surface and needs no fork-gate or gx exemption.

- **`check`** — runs on **all** PRs (incl. forks). `contents: read`, no token, default checkout (the merge ref is fine — nothing privileged runs). `mise run docs` then `git diff --exit-code`. On a diff it fails with an explicit message to run `mise run docs` and commit the result. This is the **required status check**; being token-free it is provably safe to run against untrusted fork code.
- **`generate`** — **fork-gated** (`if: github.event.pull_request.head.repo.full_name == github.repository`). `contents: write` scoped to the job, App token, checks out the PR head, runs `mise run docs`, and commits+pushes the output onto the PR branch only if there is a diff. On same-repo PRs this auto-fixes the staleness; the push re-triggers `check`, which then passes. On fork PRs it is skipped, so the contributor only ever sees `check` fail.

The build itself lives in `mise.toml`'s `[tasks.docs]` — one recipe shared by `check`, `generate`, and `update-version.yml`, and the same `mise run docs` a contributor runs locally. This removes the three-way duplication of `pnpm install && pnpm run build` and makes the failure message a single copy-pasteable command.

Mechanics and safety:

- **Commit method:** plain `git commit` + `git push` to the PR head using the App token. No new action dependency. The PR feature branch is **not** covered by `required_signatures` (the ruleset targets `~DEFAULT_BRANCH` only), so an unsigned branch commit is fine; the squash-merge commit on `main` is signed by GitHub (`allowed_merge_methods: [squash]`).
- **No infinite loop:** `generate`'s push re-triggers the workflow on `synchronize`, but the second run regenerates identical output, finds no diff, and pushes nothing. The guard is "commit only if `git diff` is non-empty."
- **gx policy:** only `generate` references the secret / writes / checks out PR head, and it is fork-gated — clearing `excessive-permissions` and `unprotected-secrets`. `pr-head-checkout` still matches `generate` statically (gx can't see the `if:` gate), so `update-docs.yml` is added to that rule's scoped ignore in `.github/gx.toml`, alongside `gx.yml`'s `tidy`. `check` references nothing privileged, so it triggers no rule.

Why not one job with `GITHUB_TOKEN` and no secret: a same-repo push made with the built-in `GITHUB_TOKEN` does not re-trigger workflows, so the regenerated commit would not re-run the strict required checks (`strict_required_status_checks_policy: true`) and could be blocked from merging on a stale check set. The App token (a distinct identity) is what makes the re-trigger happen. Hence `generate` needs the App token, while `check` needs no token at all.

### D3: Renovate auto-merge via platform automerge

Add `"automerge": true` to `renovate.json`. `platformAutomerge` defaults to `true`, so merging is delegated to GitHub-native auto-merge, which respects the ruleset; `required_approving_review_count: 0` means no approval is needed, and the 5 existing required checks satisfy the "must have ≥1 required check" precondition. No workflow added; no need to set `platformAutomerge` explicitly.

### D4: bypass-actor removal is external and concurrent

The ruleset's `bypass_actors` entry is removed in the external ruleset code as part of the same rollout — **after** the workflow changes are merged and a release has been verified to complete through PRs (so we never have "no bypass + still pushing directly" mid-rollout).

## Automated Test Strategy

The critical path is the release chain end-to-end; it has no unit-testable surface, so verification is operational:

- **Version-bump PR carries the changelog**: dispatch `update-version.yml` (or wait for the schedule) and confirm the opened PR includes a regenerated `changelog.md` for the new version alongside `config/version.json`.
- **Tag-on-merge**: merge a version-bump PR and confirm `prepare-release.yml` creates `refs/tags/X.Y.Z` from the merged commit without pushing any commit, and that `release.yml` then fires (`push: tags: ['*']`).
- **No spurious release**: confirm that a change to `changelog.md` alone (no version change) does not produce a tag (`createGitTag.js` no-ops on an already-tagged version) — and note `prepare-release.yml` no longer triggers on `changelog.md` at all.
- **Renovate**: confirm the next Renovate PR auto-merges on green and a failing-check PR does not.
- **Negative test**: after bypass removal, confirm any residual direct-push attempt is rejected by the ruleset.

No new test infrastructure; these are CI observations recorded in tasks.

## Observability

- The docs PR's number and auto-merge enablement are logged to the run summary, so a stuck docs update is traceable.
- `createGitTag.js` already no-ops idempotently; it should log whether it created or skipped the tag so a missing release is diagnosable.
- Failure is **not** silent: if a version-bump PR's checks fail, the PR stays open (visible in the PR list) and nothing merges, so no tag and no release — an absent release is the signal. `prepare-release.yml` only ever runs on a merged version change, so it cannot tag a version that wasn't reviewed.

## Risks / Trade-offs

- **[Changelog drifts from the tagged commit]** → not a real risk: the changelog is generated for the new version inside the same PR that bumps it, so the merged commit already contains the matching changelog. `release.yml` regenerates Release notes from history independently anyway.
- **[Spurious release from a changelog edit]** → removed: `prepare-release.yml` no longer triggers on `changelog.md`, only on `config/version.json`; and `createGitTag.js` no-ops on an already-tagged version.
- **[Mid-rollout gap: bypass removed while a workflow still pushes directly]** → D4 sequences bypass removal *after* a verified PR-based release.
- **[GitHub-native auto-merge merges a failing PR]** → not reachable (5 required checks present); the renovate change must not remove that precondition.
- **[App-token PR / tag does not trigger workflows]** → not a risk: the App token is distinct from `GITHUB_TOKEN`, so its PRs and tag pushes trigger workflows normally.

## Migration Plan

1. Land the `update-version.yml`, `prepare-release.yml`, `update-docs.yml`, `renovate.json` changes via PR.
2. Verify a full release completes through the PR flow (dispatch `update-version.yml` or next real version bump → merge → tag → release).
3. Remove the `bypass_actors` entry in the external ruleset code.
4. Confirm a subsequent direct-push attempt is rejected and releases still succeed.

Rollback: restore the `bypass_actors` entry externally and revert the workflows to the `github-api-commit-action` direct push.

## Open Questions

- **Does `release.yml`'s `push: tags: ['*']` fire when the tag is created via the App token?** Expected yes (App token ≠ `GITHUB_TOKEN`, so tag pushes trigger workflows), but confirm during the verification release before removing the bypass.
