# Research: automerge-approved-automation-prs

Verification pass over an existing, fully-drafted change (`proposal.md`, `design.md`, `tasks.md`, spec delta). All repository facts below were re-read live via `gh api` on 2026-08-14, independently of the design's own 2026-08-13 reading.

**Headline:** the change's mechanism is correct and empirically proven in this repository. Two spec defects sit in its blast radius that the change does not currently address, and one open question (task 1.2) is now answered — with an answer that contradicts a stated invariant.

## Context

The weekly version-bump PR is the only automation PR that does not self-merge.

```
  update-version.yml (cron: MON-FRI)
        │
        ├─ update-flutter-version ─┐
        ├─ update-android-version ─┼──▶ compose-and-open-pr
        └─ update-windows-version ─┘         │
                                              ├─ mint verified-commit App token   (:432)
                                              └─ peter-evans/create-pull-request  (:449)
                                                     │
                                                     ▼
                                              PR opened ── NO auto-merge enabled
                                                     │
                                    approve ─────────┤
                                    click "Merge" ───┘   ◀── the manual step

  Renovate                        ▶ PR opened ── auto-merge ENABLED at open time
                                                     │
                                    approve ─────────┴──▶ merges in ~2s
```

Verified: `.github/workflows/update-version.yml:449-457` is the repo's **only** `create-pull-request` call, and the step has no `id:` and no follow-up step. The App token is minted 17 lines above it. `.github/renovate.json:11` carries `"automerge": true`.

## Findings

### 1. The mechanism claim is correct — proven three times over

The design asserts approval is the last unmet merge requirement for bot-authored PRs, so enabling auto-merge at open time yields merge-on-approval. Timeline data confirms it:

| PR | Author | Auto-merge enabled by | Approved | Merged | Δ |
|---|---|---|---|---|---|
| #541 | `renovate[bot]` | `renovate` @ `02:16:12` | `09:13:37` | `09:13:39` | **2s** |
| #542 | `renovate[bot]` | `renovate` | `07:12:09` | `07:12:11` | **2s** |
| #523 | `verified-commit[bot]` | **`gmeligio` @ `10:29:30`** | `10:30:08` | `10:30:10` | **2s** |
| #530 | `verified-commit[bot]` | **`gmeligio` @ `15:31:50`** | `15:31:41` | `15:44:56` | — |
| #547 | `verified-commit[bot]` | *(none)* | `07:22:19` | `07:23:05` | manual click |

**#523 is the decisive row.** Auto-merge was enabled on a `verified-commit`-authored PR at `10:29:30`; the PR sat green and unmerged for 38 seconds; approval landed `10:30:08`; merge `10:30:10`. That is precisely the behaviour this change wants, already demonstrated on this exact PR class. The design reached the right conclusion from #541/#542 alone; #523/#530 are stronger evidence it did not cite.

Ruleset re-read live (`rulesets/1959230`), matching `design.md:5-16` exactly: `require_code_owner_review: true`, `required_approving_review_count: 0`, `allowed_merge_methods: ["squash"]`, `strict_required_status_checks_policy: true`, 6 required checks, `dismiss_stale_reviews_on_push: true`. Repo: `allow_auto_merge: true`, squash-only.

### 2. Task 1.2 answered, and the bypass it found has since been removed

`design.md:30` speculated that maintainer PRs merge unreviewed either via a repository-admin bypass or because GitHub forbids self-approval. The first was wrong and the second is right, but the investigation turned up a separate problem: at the time of research the live `bypass_actors` list had one entry, an `Integration` bypass (`bypass_mode: "always"`) belonging to the `verified-commit` App — the very App this change makes the merging identity.

It was orphaned config. The job that needed it, `prepare-release.yml`'s `update-changelog`, was deleted by p10 on 2026-06-02; it had produced the only two direct-to-`main` pushes in the repository's history. All four workflows minting the App token were audited and none writes to the protected ref — three push to PR branches (outside the ruleset's `~DEFAULT_BRANCH` condition) and `prepare-release.yml` creates a tag, which a `target: "branch"` ruleset never gated.

**Resolved on 2026-08-24.** The entry was removed at the source. Re-verified live:

```
gh api /repos/gmeligio/flutter-docker-image/rulesets/1959230 --jq '.bypass_actors'
  →  []                       (updated_at 2026-08-24T14:42:06+02:00)

all seven rule types intact; require_code_owner_review: true
allowed_merge_methods: ["squash"]; enforcement: active
```

`openspec/specs/ci-repo-governance/spec.md:53` — "The default-branch ruleset has no bypass actor" — is therefore now **true as written**, and its two scenarios (direct push rejected; tag creation unaffected) describe the current state. No spec correction is needed; the requirement stands unchanged.

Why maintainer PRs (#531, #538, #540, #543) still merge with zero reviews is the second hypothesis: GitHub does not accept a PR's author as a satisfying code-owner reviewer, and `required_approving_review_count` is `0`, so no numeric floor blocks the merge. The bypass was `Integration`-typed and never applied to a user account, so its removal does not change this. It is why auto-merge on maintainer-authored PRs stays out of scope.

### 3. Two stale specs in the change's blast radius

**(a) `ci-workflow-readability/spec.md:57-76` mandates a job that does not exist.**

> "SHALL be a single workflow `.github/workflows/prepare-release.yml` with two sequential jobs (`update-changelog` → `create-tag` via `needs:`)"

Live `prepare-release.yml` has **one** job — `create-tag` (line 28). p10 deliberately deleted `update-changelog` (`archive/.../proposal.md:27`) and updated `ci-repo-governance` while leaving this spec describing the pre-p10 world. Two specs now disagree about whether `prepare-release.yml` writes to `main`: this one mandates a changelog-commit job, while `ci-repo-governance:11` forbids direct pushes.

This matters to *this* change because line 59 is currently the **only** spec sentence carrying the App-identity invariant ("The App-token identity used to push SHALL be unchanged so the tag push still triggers `release.yml`") — the same invariant the change's new requirement introduces. Delete the stale requirement without re-homing that clause and the invariant is lost; the change's new requirement is its correct new home, so the edits belong together.

**(b) `flutter-version-update/spec.md:5` says "monthly".** Cron is `0 0 * * MON-FRI` — weekday-daily. The change's own artifacts say "weekly". Three different cadences, none matching the code. Cosmetic, cheap to fix.

### 4. Structure and placement are correct

- **Only possible home.** `compose-and-open-pr` is the sole job holding both the App token (`:432`) and a PR number (`:449`). No other workflow opens a PR — the App token's three other sites (`update-docs.yml:75`, `gx.yml:54`, `prepare-release.yml:43`) push to existing branches or create tags. Nothing to duplicate, nothing to factor out.
- **No composite action warranted.** `.github/actions/` holds multi-caller concerns only; a one-step, one-caller action is below that bar.
- **gx-clean.** `actions/github-script` is already pinned in `.github/gx.toml:5` and already used twice in this same workflow (`:268`, `:391`). No new manifest entry, no `pr-head-checkout` exposure. The `pull_request_review` alternative the design rejected (`design.md:54`) would have needed a new gx exemption — the rejection holds up against the real ruleset.
- **Permissions invariant intact.** `compose-and-open-pr` declares no job-level `permissions:`, inheriting the read-only default (`:9-11`); all writes go through the App token. Task 2.7 preserves this.

### 5. Confirmed mechanics and secondary risks

- **`pull-request-number` exists in v7.0.11** (outputs: number, url, operation, head-sha, branch, commits-verified; operation ∈ created/updated/closed/none). The gating in task 2.4 is valid, and matches the action's own documented `if: steps.cpr.outputs.pull-request-number` guard.
- **"Clean status" analysis is right.** `enablePullRequestAutoMerge` errors when nothing blocks the PR; the common cause is absent branch protection. Cannot occur here at open time (checks unrun, unapproved). Treating it as a warning rather than falling back to a direct merge is the correct call.
- **A March 2026 report of 422 on enabling auto-merge is merge-queue-specific** (`mergeMethod: "GROUP"`, `merge_queue` rule) and does not apply — this repo has no merge queue, and Renovate enabled auto-merge successfully on 2026-08-10, months later.
- **Stale-branch risk is real** (`design.md:115`): `strict_required_status_checks_policy: true` + no auto-rebase. Note `allow_update_branch: true` is set, so a future `update_pull_request_branch` mitigation is available without a settings change.
- **Docs-push dismissal risk is real** (`design.md:116`): `update-docs.yml:14-18` triggers on `config/version.json` in `pull_request`, so it does push to the bump PR branch. Combined with `dismiss_stale_reviews_on_push: true`, ordering matters. Task 4.4 covers it.
- **Version drift, pre-existing and out of scope:** `gx.toml:5` pins `actions/github-script` at `^9.0.0` but all ten uses repo-wide are v8.0.0; `gx.toml:16` pins `create-pull-request` at `^8.0.0` while the workflow uses v7.0.11. Not caused by this change; worth a separate issue.

## Options

With the bypass removed at its source, the spec-correction work that Option B existed to carry is gone; `ci-repo-governance:53` is true unmodified. What remained was a scope question, since the maintainer chose to fold every finding into this change rather than defer any.

| Approach | Pros | Cons |
|---|---|---|
| **A. Ship the workflow step only** | Smallest diff; mechanism proven by #523/#530 | Leaves the silent stale-branch stall, which the change itself makes worse by removing the click that surfaced it; leaves three specs describing a world that no longer exists |
| **B. Step + stale-branch handling + all stale specs** *(chosen)* | The approval genuinely becomes the last action; every spec the change touches or contradicts tells the truth; nothing deferred | Wider diff — four capability specs instead of one |

```
   OPTION A                       OPTION B (chosen)
   ┌──────────────┐               ┌──────────────┐
   │ workflow     │               │ workflow     │
   │  + automerge │               │  + automerge │
   └──────┬───────┘               │  + update    │
          │                       │    branch    │
   ┌──────┴───────┐               └──────┬───────┘
   │ ci-repo-gov  │               ┌──────┴───────┐
   │ automerge req│               │ ci-repo-gov  │
   └──────────────┘               │ automerge +  │
                                  │ stale-branch │
   stale-branch stall ✗           └──────┬───────┘
   readability req.   ✗           ┌──────┴───────┐
   cadence x2         ✗           │ readability  │
                                  │ cadence x2   │
                                  └──────────────┘
```

## Recommendation

**Option B, as directed — everything fixed in this change, no follow-ups.**

```
  BEFORE                                    AFTER
  ┌─────────────────────────┐               ┌─────────────────────────┐
  │ update-version.yml      │               │ update-version.yml      │
  │  create-pull-request    │               │  create-pull-request    │
  │  (no id, no follow-up)  │               │  id: create_pr          │
  └───────────┬─────────────┘               │  + update stale branch  │
              │                             │  + enable auto-merge    │
        approve ──▶ CLICK MERGE             └───────────┬─────────────┘
                                                  approve ──▶ merges (2s)
        stale branch ──▶ click surfaces it        stale branch ──▶ updated
                                                                 before review

  specs                                      specs
   ├ ci-repo-gov automerge ── "approvals      ├ ci-repo-gov ── ruleset gate ✓
   │   not required"           ✗ FALSE        │   + stale-branch req.     ✓
   ├ ci-repo-gov bypass ── "no bypass         ├ ci-repo-gov bypass ── unchanged,
   │   actors"             ✗ was FALSE        │   now TRUE in fact        ✓
   ├ readability ── two-job graph  ✗          ├ readability ── one job    ✓
   └ cadence ── "monthly" x2       ✗          └ cadence ── weekday        ✓
```

What landed:

1. **Workflow** — `id: create_pr`, a branch-update call when the PR is behind `main`, then `enablePullRequestAutoMerge`. Both wrapped in `try`/`catch` → `core.warning`; neither can fail the job or lose the bump PR.
2. **`ci-repo-governance`** — the corrected auto-merge requirement, plus a new stale-branch requirement. The bypass requirement is untouched: removing the bypass made it true.
3. **`ci-workflow-readability`** — release-prep corrected to the single `create-tag` job that exists, absorbing the App-token identity clause that was previously only stated there.
4. **`flutter-version-update`** and **`windows-version-tracking`** — cadence corrected from "monthly" to weekday-scheduled. The latter needed REMOVED + ADDED, since the requirement's own name said "Monthly".
5. **Two Purpose headers** also say "monthly". Prose outside a requirement cannot be carried by a delta, so task 3.8 syncs them on archive.

**Not a finding after all:** the `gx.toml` pins (`github-script ^9.0.0`, `create-pull-request ^8.0.0`) are one major ahead of what the workflows use, which I earlier called drift. They are upgrade targets and match the current upstream latest; Renovate closes that gap. `gx lint` passes clean. Nothing to fix.

## Open Questions

None. The bypass posture question was resolved by removal (verified `[]` on 2026-08-24). The two scope questions were resolved by the maintainer: `require_code_owner_review` and `strict_required_status_checks_policy` both stay as they are, and the workflow handles the staleness that the latter causes.

## Next Steps

`/opsx:apply`. Task 1.2's precondition (`bypass_actors == []`) and 2.8's (`allow_update_branch: true`) are both confirmed as of today.

## Sources

**Code (verified live):** `.github/workflows/update-version.yml:9-11,432-439,449-457`, `prepare-release.yml:28`, `update-docs.yml:14-18`, `.github/renovate.json:11`, `.github/gx.toml:5,16,28-31`, `.github/CODEOWNERS:1`, `openspec/specs/ci-repo-governance/spec.md:53,75`, `openspec/specs/ci-workflow-readability/spec.md:57-76`, `openspec/specs/flutter-version-update/spec.md:5`, `openspec/changes/archive/2026-06-02-p10-strengthen-branch-protection/{proposal.md:8,27,tasks.md:21}`

**GitHub API:** `repos/gmeligio/flutter-docker-image/rulesets/1959230`, `/repos/.../rules/branches/main`, `/apps/verified-commit`, `/repos/.../branches/main/protection` (404 — no classic protection), GraphQL PR timelines for #523, #530, #541, #542, #547

**Web:**
- https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request
- https://github.com/orgs/community/discussions/162623 — bypass_actors not re-checked by async auto-merge path
- https://github.com/orgs/community/discussions/190610 — March 2026 422, merge-queue-specific
- https://github.com/peter-evans/enable-pull-request-automerge/issues/343 — "clean status" error
- https://github.com/peter-evans/create-pull-request/blob/v7.0.11/README.md — v7 outputs
