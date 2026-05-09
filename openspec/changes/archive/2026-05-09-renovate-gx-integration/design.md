## Context

After `adopt-gx-for-actions` (#439), the repository has three coordinated artifacts: `.github/gx.toml` (manifest), `.github/gx.lock` (resolved versions and SHAs), and `.github/workflows/gx.yml` (CI lint + tidy on PR). However, the existing `.github/renovate.json` still drives version bumps using Renovate's built-in `github-actions` manager, which edits the workflow YAML directly. The current `gx.yml` `tidy` job then runs and pushes a follow-up commit to sync `.github/gx.lock`. This works, but:

1. Manifest specifiers like `"^6"` and `"~0.3.0"` are not honored by Renovate — it walks past majors freely.
2. Two systems edit overlapping files; cross-PR races and noisy chase-commits are routine.
3. The "what versions are allowed" question has no canonical answer — `gx.toml` describes one constraint, Renovate operates on a different one, the lock records the resolution.

The repository is hosted on the **Mend Renovate App**, which forbids `postUpgradeTasks` (those require self-hosted Renovate with `allowedPostUpgradeCommands`). The single-commit-PR option from self-hosted Renovate is therefore unavailable. This design takes the next-best path: scope Renovate to a single file (`gx.toml`), and let CI propagate.

Verified beforehand:

- `gx tidy` resolves manifest specifier changes and rewrites both `gx.lock` and workflow `uses:` SHAs in a single run (`~/Code/gx/src/tidy/command.rs:97-148`). Phase 1 (`sync_manifest_actions`) only adds/removes manifest entries and does not overwrite a specifier already present, so a Renovate edit (`^6` → `^6.0.2`) survives Phase 1 untouched and is consumed by Phase 3 (`lock_sync`) and Phase 4 (`compute_workflow_patches`).
- Renovate's built-in `github-actions` manager covers both `.github/workflows/**` and `.github/actions/**` (https://docs.renovatebot.com/modules/manager/github-actions/), so disabling it must be done by manager name, not file pattern.

## Goals / Non-Goals

**Goals:**

- Make `.github/gx.toml` the only Renovate-editable file for GitHub Actions versions.
- Honor manifest specifiers (`^6`, `~0.3.0`) in Renovate's upgrade proposals so cross-major bumps require a human commit.
- Keep the existing `gx.yml` `tidy` job as the sole agent that rewrites `gx.lock` and workflow `uses:` references.
- Preserve the current monthly schedule (`* 0-3 1 * *`) for action upgrades.
- Preserve all existing non-actions Renovate rules (Dockerfile suite tracking, npm grouping, weekly cadence, etc.).

**Non-Goals:**

- Switching off the Mend Renovate App or migrating to self-hosted Renovate.
- Introducing `postUpgradeTasks` (incompatible with Mend App).
- Changing `gx`, `gx.yml`, or any workflow file behavior.
- Changing the schedule cadence or grouping for non-actions dependencies.
- Adding a new scheduled `gx upgrade` cron workflow (option A from the prior research; rejected here in favor of letting Renovate continue to be the upgrade trigger).

## Decisions

### Decision 1: Use a Renovate `customManagers` regex over `gx.toml`, not Renovate's TOML manager

Renovate has no first-class manager for `gx.toml`. Two options:

- **Custom regex manager (chosen)**: One `customManagers` entry with a regex over `gx.toml`. Direct, debuggable, well-supported.
- **Upstream a `gx` manager into Renovate**: A months-long external dependency. Out of scope.

The regex must extract:

- `depName` — full string from the manifest line (e.g., `github/codeql-action/upload-sarif`). Used in PR titles, dashboards, changelogs.
- `packageName` — first two slash-separated segments only (`github/codeql-action`). Used by the `github-tags` datasource to query the right repo. The non-capturing group `(?:/[^"]+)?` swallows the optional subpath.
- `currentValue` — the specifier (`^6`, `~0.3.0`).

Final pattern:

```
"(?<depName>(?<packageName>[^/"]+/[^/"]+)(?:/[^"]+)?"\s*=\s*"(?<currentValue>[^"]+)"
```

Datasource: `github-tags`. Versioning: `npm` (handles `^` and `~`). Extract template: `^v?(?<version>.+)$` (strip `v` prefix from tags so npm versioning compares cleanly).

Renovate docs (https://docs.renovatebot.com/configuration-options/#custommanagers) recommend "use only one method" per field but do not forbid two named captures from the same regex. We intentionally capture both `depName` and `packageName` because they differ for subpath actions; if Renovate rejects this combination at validation time, fall back to a `packageNameTemplate` Handlebars expression.

### Decision 2: Disable Renovate's built-in `github-actions` manager via `matchManagers`

Two options for stopping Renovate from editing workflow files:

- **`matchManagers: ["github-actions"]` + `enabled: false` (chosen)** — disables the manager by name. Clean, explicit, future-proof if Renovate adds new file patterns to the manager.
- **`ignorePaths` covering `.github/workflows/**` and `.github/actions/**`** — file-pattern-based. Brittle if Renovate's coverage changes; also affects unrelated managers if any.

Manager-based disabling is the documented idiomatic path.

### Decision 3: Reuse the existing `gx.yml` `tidy` job; do not introduce a new workflow

The `tidy` job in `.github/workflows/gx.yml` already runs `gx tidy` on every PR (when not from a fork) and pushes the result via the `VERIFIED_COMMIT_*` GitHub App. After Path 2, that job's role expands from "sync the lock to match Renovate's workflow edits" to "resolve Renovate's manifest edit into lock + workflow rewrites". Both are well within `gx tidy`'s capability and the existing workflow's permission scope. No workflow changes are needed.

### Decision 4: Keep the schedule on the rule that targets `gx.toml`

The current `renovate.json` puts `schedule: ["* 0-3 1 * *"]` on the `github-actions` package rule. After this change, that rule is gone. The schedule moves to a new rule keyed on `matchFileNames: [".github/gx.toml"]`, preserving the monthly-first-day cadence. Grouping name `github-actions` is preserved so existing PR-routing rules (if any in branch-protection or auto-merge configs) continue to apply.

### Decision 5: Accept the two-commit PR shape

Each Renovate upgrade PR will contain:

1. Renovate's commit: 1-line edit in `gx.toml`.
2. gx-bot's commit (via `grafana/github-api-commit-action`, App-token-signed): updated `gx.lock` + workflow files + composite actions.

A one-commit alternative requires `postUpgradeTasks`, which is unavailable on the Mend App. Two commits is acceptable: it matches the current observed PR shape (Renovate + chase-commit), and the "verified" App-token commit on top makes intent obvious in `git log`.

### Decision 6: Do not change `.github/gx.toml` or `gx.lock` as part of this proposal

This is a pure config refactor on the Renovate side. Manifest specifiers stay as currently committed. Future tightening of specifiers (e.g., switching `^6` to `~6.0.0` to forbid minor bumps) is a separate decision and a separate change.

## Risks / Trade-offs

- **Risk**: The two-named-capture regex (`depName` + `packageName` in the same `matchStrings`) may fail Renovate's config validation or runtime extraction. → Mitigation: dry-run validation step in tasks (`renovate-config-validator`); fallback design uses a Handlebars `packageNameTemplate` instead.
- **Risk**: `npm` versioning may misinterpret action tags that don't follow strict semver (e.g., `v6.0` instead of `v6.0.0`). → Mitigation: `extractVersionTemplate` strips the `v` prefix; if loose tags persist, Renovate will skip those bumps rather than corrupting them. `gx lint` would surface any resulting inconsistency.
- **Risk**: Lint (in `gx.yml`) runs in parallel with `tidy` and may fail on the first commit (manifest ahead of workflows). The PR shows a transient red check that flips green after `tidy` pushes its commit. → Mitigation: behavior is identical to the current chase-commit pattern; documented in tasks; out-of-scope to restructure `gx.yml`.
- **Risk**: An action used in workflows but missing from `gx.toml` would not be picked up by Renovate (since the only manager is now manifest-scoped). → Mitigation: `gx tidy` adds missing actions to the manifest on PR; `gx lint` flags unsynced manifest entries. A one-shot `gx tidy` locally before merging this proposal verifies completeness.
- **Trade-off**: Loses Renovate's ability to identify exact patch-level upgrades for actions whose tags don't follow semver. The lock will still be regenerated against the manifest specifier whenever upstream publishes a tag in range — just not driven by a Renovate PR for non-semver-compliant tags. Acceptable for the action set in this repo.
- **Trade-off**: Renovate's PR body will reference `depName` (full string with subpath); the github-tags lookup uses `packageName` (org/repo). The PR will list a `package: github/codeql-action`, dep: `github/codeql-action/upload-sarif`. Slight cosmetic asymmetry; not a correctness issue.

## Migration Plan

1. Local pre-flight: run `gx tidy` against the current tree; confirm zero diff. This validates that workflows, manifest, and lock are mutually consistent before changing Renovate.
2. Locally validate the new `renovate.json` with the Renovate config validator and a `--dry-run=full` against the local checkout. Confirm Renovate finds `gx.toml`, parses each line, and resolves expected `currentVersion` for at least three sample actions (one with subpath, one with caret, one with tilde).
3. Open a PR with the new `renovate.json`. The change is isolated to one file.
4. Watch the next Mend Renovate cycle. Confirm:
   - No PRs editing `.github/workflows/**` or `.github/actions/**` are produced.
   - Any new PR edits only `.github/gx.toml`.
   - `gx.yml`'s `tidy` job adds the lock + workflow commit and `gx lint` passes on the head commit.

**Rollback**: revert the `renovate.json` change. Behavior returns to the prior (workflow-editing) Renovate model. No data migration is required because no other artifacts are touched.

## Automated Test Strategy

This change has no application code; verification is configuration-level and observational.

- **Critical path**: Renovate scans `gx.toml`, opens a PR with one `gx.toml` edit, `gx.yml` propagates lock + workflow updates, `gx lint` passes.
- **Pre-merge verification**:
  - `npx --package renovate -- renovate-config-validator .github/renovate.json` — must pass.
  - Local Renovate dry-run (`renovate --platform=local --dry-run=full`) — must list expected upgrades for `gx.toml` entries and zero upgrades from the now-disabled `github-actions` manager.
  - Local `gx tidy` against the tree before opening the PR — must produce no diff (proves baseline consistency).
- **Post-merge verification (first Renovate cycle, time-bounded)**: confirm one Renovate PR opens, edits only `gx.toml`, `gx.yml` `tidy` succeeds, and `gx lint` passes on the merged head.
- **No new test infrastructure**. The existing `gx lint` job in `.github/workflows/gx.yml` is the on-going invariant check.

## Observability

- **Renovate-side failure surface**: Mend Renovate dashboard shows manager-extraction errors per repo. If the regex fails to match any line in `gx.toml`, Renovate's logs surface a warning and produce zero PRs for actions — visible as "no upgrades opened this cycle" on the dashboard. This is *silent* on the GitHub side; first observation is the absence of expected PRs after the cycle.
- **gx-side failure surface**: `gx tidy` failures in the `gx.yml` `tidy` job appear as failed CI checks on the PR. `gx lint` failures appear as failed CI checks on every commit.
- **Drift surface**: if a Renovate PR ever lands without the `tidy` follow-up commit (e.g., `tidy` job timed out, App token expired), `gx lint` fails on the PR head and merge is blocked. This is the load-bearing safety net.
- **What is logged**: nothing new. `gx.yml` already prints tidy/lint progress; Renovate's logs are visible via the Mend dashboard.
- **Can a failure be silent?**: yes — if Renovate's custom manager extracts zero matches, there is no GitHub-side signal until someone notices that monthly action upgrade PRs stopped arriving. Mitigation: the migration plan's local dry-run is the front-loaded check; running it before merge converts the silent failure into a loud, pre-merge one.

## Open Questions

- Does Renovate's config validator accept the two-named-capture regex (`depName` + `packageName` in the same `matchStrings`)? Tasks include the verification step; if validation fails, fall back to `packageNameTemplate` with a Handlebars conditional.
- Should the `github-actions` group label be preserved on the new rule (`groupName: "github-actions"`) for any downstream branch-protection or auto-merge config? Default: yes, unless evidence emerges that no rule depends on it.
