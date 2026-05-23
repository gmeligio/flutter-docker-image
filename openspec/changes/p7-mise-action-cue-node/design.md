## Context

Three CI tools — `cue`, `node`, and `gx` — are currently installed by per-step third-party actions:

- `cue` v0.15.0 via `jaxxstorm/action-install-gh-release` in 9 jobs across `ci.yml`, `build.yml`, `update_version.yml`. Each step duplicates the same `repo`, `tag`, and `digest` inputs.
- `node` LTS via `actions/setup-node@v6` (with `cache: npm`, lockfile at `docs/src/package-lock.json`) in 3 jobs across `build.yml`, `update_docs.yml`, `update_version.yml`.
- `gx` v0.7.1 via `jaxxstorm/action-install-gh-release` in 2 jobs of `gx.yml` (the `lint` and `tidy` jobs that enforce the action manifest itself).

A `mise.toml` already exists at the repo root pinning `cue = "0.15.0"`, but no workflow consumes it. CI run 26333167642 hit `401 Bad credentials` from the jaxxstorm action's call to `GET /repos/cue-lang/cue/releases/tags/v0.15.0`, exposing the fragility of the per-step installer pattern.

The `actions-version-tracking` capability already mandates that `.github/gx.toml`, `.github/gx.lock`, and workflow `uses:` SHAs stay mutually consistent on the merging PR. This refactor must respect that invariant when adding/removing manifest entries.

```
   BEFORE                                       AFTER

   mise.toml (cue = "0.15.0")  ── ignored       mise.toml ── single source of truth
                                                 ├── cue = "0.15.0"
   Workflow step ×9 (cue):                       ├── node = "lts"
     jaxxstorm/action-install-gh-release         └── "github:gmeligio/gx" = "0.7.1"
       repo: cue-lang/cue
       tag: v0.15.0                              Workflow step ×14:
       digest: 06925fc1…d460                       jdx/mise-action@v4
                                                   (no inputs)
   Workflow step ×3 (node):
     actions/setup-node@v6
       node-version: lts/*
       cache: npm

   Workflow step ×2 (gx):
     jaxxstorm/action-install-gh-release
       repo: gmeligio/gx
       tag: v0.7.1
       digest: 66328434…ecd9
```

## Goals / Non-Goals

**Goals:**

- Single source of truth for `cue`, `node`, and `gx` versions: `mise.toml`.
- Eliminate the 9× CUE-install duplication, 3× node-install duplication, and 2× gx-install duplication in workflow files.
- Fix the failing `Setup CUE` step by adopting an action that defaults `github_token` to `${{ github.token }}`.
- Fully remove `jaxxstorm/action-install-gh-release` and `actions/setup-node` from `.github/gx.toml` (no remaining workflow references after this change).
- Keep `.github/gx.toml`, `.github/gx.lock`, and workflow `uses:` SHAs mutually consistent on the migrating PR.

**Non-Goals:**

- Re-introducing npm package caching. The previous `cache: npm` on `actions/setup-node` is intentionally dropped for now; a follow-up may add an `actions/cache` step keyed on `docs/src/package-lock.json` if cold `npm ci` cost becomes a problem.
- Absorbing other tooling into `mise.toml` (Docker buildx, gradle, gh CLI, etc.). Out of scope.
- Changing tool *versions*. `cue` stays at `0.15.0`; `node` stays at LTS; `gx` stays at `0.7.1`.
- Changing what `cue vet` / `cue export` / `cue eval` / `npm ci && npm run …` / `gx lint` / `gx tidy` do.

## Decisions

### Decision 1: Adopt `jdx/mise-action@v4` (vs. install `mise` via a shell step)

**Choice:** Use `jdx/mise-action@v4`.

**Rationale:** The action handles install, version pinning of `mise` itself, tool-cache, and `github_token` defaulting. A hand-rolled `curl | sh` step would re-implement this and skip the cache. The action is the documented path.

**Alternatives considered:**
- Shell-installing `mise` per job — more code per workflow, no cache.
- Keeping the jaxxstorm action and just passing `token: ${{ secrets.GITHUB_TOKEN }}` — fixes the immediate 401 but does not address the 9× duplication. Rejected.

### Decision 2: `node = "lts"` (floating alias) vs. pinned major

**Choice:** `node = "lts"` in `mise.toml`.

**Rationale:** Matches the existing `node-version: lts/*` behavior in `actions/setup-node`. Zero behavior change for docs builds. A future change can pin a specific LTS if reproducibility issues surface.

### Decision 3: Install `gx` via mise using the `github:` backend

**Choice:** Add `"github:gmeligio/gx" = "0.7.1"` to `mise.toml` and bootstrap it in `gx.yml` via `jdx/mise-action@v4`.

**Rationale:** `gmeligio/gx` is not in the mise registry, but mise's `github:` backend handles arbitrary GitHub releases. This is needed so we can fully remove `jaxxstorm/action-install-gh-release` from `.github/gx.toml` — it was kept alive only by the two `gx` install steps inside `gx.yml`. Without migrating `gx`, the spec's "fully remove" requirement could not hold.

**Alternatives considered:**
- `ubi:gmeligio/gx@0.7.1` — works today but mise marks the `ubi` backend as deprecated for removal in mise 2027.1.0. Skipped.
- Keep `jaxxstorm/action-install-gh-release` only for `gx`. Rejected: leaves a one-consumer surface in `.github/gx.toml` that confuses the spec invariant.

**Chicken-and-egg:** `gx.yml` is the workflow that validates `.github/gx.toml`/`.github/gx.lock` itself. After this change, that workflow bootstraps `gx` via `mise-action` (an action that is itself pinned by SHA in `.github/gx.toml`). This is acceptable: if `mise-action` is ever yanked or compromised, the standard checkout-time SHA pin protects us — but `gx tidy` cannot self-heal in that scenario. The risk is the same as today (where `gx.yml` already depends on `jaxxstorm/action-install-gh-release` via SHA).

### Decision 4: Drop npm package caching for now

**Choice:** No npm cache step in the migrated workflows.

**Rationale:** User-confirmed acceptable trade-off. Keeps the diff small and avoids a separate `actions/cache` step in three workflows. Re-adding it is a one-step follow-up if cold `npm ci` (~10–20 s) becomes painful.

### Decision 5: Treat manifest sync as part of the same PR

**Choice:** Add `jdx/mise-action = "^4"` to `.github/gx.toml`, remove `jaxxstorm/action-install-gh-release` and `actions/setup-node` from it, and reconcile `.github/gx.lock` in the same PR that edits the workflow files.

**Rationale:** The `actions-version-tracking` spec explicitly requires manifest, lock, and workflow `uses:` SHAs to be mutually consistent on merge. Splitting this across PRs would temporarily violate the invariant.

### Decision 6: No delta on `actions-version-tracking`

**Choice:** Do not author a delta against `actions-version-tracking`. The new capability `ci-runtime-tool-versioning` (see `specs/`) is the only spec change.

**Rationale:** The `actions-version-tracking` requirement text — "the manifest declares the version constraint for every distinct GitHub Action referenced by `uses:`" — is unchanged. The set of referenced actions shifts (gain `jdx/mise-action`, drop two others), but that is an *instance* of the requirement, not a modification of it.

## Risks / Trade-offs

- **[Risk] `jdx/mise-action@v4` hits GitHub's API rate limit and the docs job fails.** → Mitigation: the action defaults `github_token` to `${{ github.token }}` (the same default the project already uses elsewhere). If 60-req/hr ever becomes a problem with a missing token, the per-job `permissions: contents: read` is sufficient for releases reads.
- **[Risk] `node = "lts"` resolves to a different major version than what `lts/*` currently picks at run time, breaking the `mdx-to-md` / React 19 docs build.** → Mitigation: mise resolves `lts` to the same upstream LTS metadata that `setup-node` uses; on first migrated run, observe the resolved version in the mise install log. If a mismatch surfaces, pin to a specific major (`node = "22"` or similar) in a follow-up.
- **[Risk] First runs after merge re-download `cue` and `node` per job, slowing builds.** → Mitigation: `jdx/mise-action` enables tool-install caching by default, keyed on `mise.toml` hash + OS. Cost is paid once.
- **[Risk] Dropping `cache: npm` materially slows the docs build.** → Mitigation: user accepted this; revisit with an `actions/cache` step if measured cost is painful.
- **[Risk] `.github/gx.lock` reconcile is missed on the same PR**, leaving a transient manifest-vs-workflow mismatch. → Mitigation: tasks.md enforces a single PR for manifest, lock, and workflow edits; the existing CI consistency check (per `actions-version-tracking`) catches mismatches before merge.

## Automated Test Strategy

This change has no unit-testable surface — it is workflow YAML and a TOML manifest. Verification is "does CI go green on the migrating PR" at the level of the actual workflows:

- **`ci.yml` (test_image)** — runs on push/dispatch. Must succeed after migration: this is the workflow that's currently red.
- **`build.yml`** — invoke via `workflow_dispatch` once on the PR branch (or wait for the next push event that targets it). Must reach the `cue vet` and `cue export` steps and succeed.
- **`update_docs.yml`** — invoke via `workflow_dispatch` on the PR branch; must complete the `npm ci && npm run build` step.
- **`update_version.yml`** — invoke via `workflow_dispatch` on the PR branch; must reach both CUE-using and Node-using job stages.
- **Manifest consistency check** — the existing CI step (or pre-merge action) that the `actions-version-tracking` capability mandates must pass with the new `jdx/mise-action` entry and the two removals.

No new test infrastructure required.

## Observability

Failures surface through the standard GitHub Actions UI:

- `jdx/mise-action@v4` logs the resolved `cue` and `node` versions on each run — visible in the step's `Run mise install` output. This is the canonical signal that `mise.toml` was read correctly.
- A wrong tool version surfaces as a downstream step failure (`cue vet` validation error, `npm ci` engine mismatch, etc.) — never silent.
- Manifest drift between `.github/gx.toml`, `.github/gx.lock`, and workflow `uses:` SHAs is already caught by the `actions-version-tracking` consistency check at PR time.

No new logging or alerting is added; existing channels suffice.

## Migration Plan

1. Stage all changes on one branch and open one PR (per `actions-version-tracking` consistency requirement).
2. Land changes in this order inside the PR commits (or as one commit, reviewer's preference):
   a. Update `mise.toml` (add `node = "lts"`).
   b. Update `.github/gx.toml` (add `jdx/mise-action`).
   c. Regenerate `.github/gx.lock` via the project's lockfile-sync mechanism.
   d. Replace all `Setup CUE` and `Setup NodeJS` steps in the four affected workflows.
   e. Remove `jaxxstorm/action-install-gh-release` and `actions/setup-node` entries from `.github/gx.toml` and `.github/gx.lock`.
3. Trigger each affected workflow once on the PR branch to confirm green CI before merge.
4. **Rollback:** straightforward `git revert` of the single PR. No external state to unwind. Tool caches in GitHub Actions will repopulate on the next run.

## Open Questions

None. All scoping decisions are confirmed.
