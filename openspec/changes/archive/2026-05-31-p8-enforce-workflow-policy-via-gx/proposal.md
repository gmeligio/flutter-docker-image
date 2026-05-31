## Why

p7 (`ci-workflow-hardening`) defines the structural properties every workflow under `.github/workflows/` SHALL meet: top-level `permissions:`, `concurrency:` on push/schedule triggers, SHA-pinned actions, no unreviewed `pull_request_target`, fork-secret gates on PR-triggered workflows. Today those properties are enforced **by maintainer review**. A new workflow that omits a `permissions:` block, or a contributor PR that references `secrets.*` without a fork gate, depends on the reviewer remembering the spec.

The previous p8 proposal (`p8-extract-workflow-composites`, deleted in favor of this change) tried to enforce the properties **by abstraction** — funnel every workflow's setup through composite actions that bake in the gates. That approach trades one drift surface (inlined setup steps) for another (composites that callers can simply not use), still requires manual review to catch, and added two new files and a README for ~5 callers — under the break-even point.

The `gx` CLI already runs in this repo's CI (`.github/workflows/gx.yml` calls `gx lint`). The companion change `add-workflow-security-rules` in the `gx` repo (PR [gmeligio/gx#87](https://github.com/gmeligio/gx/pull/87)) adds six workflow-level security rules — `missing-permissions`, `excessive-permissions`, `dangerous-trigger`, `pr-head-checkout`, `missing-concurrency`, `unprotected-secrets` — that together cover the structural properties `ci-workflow-hardening` mandates. **These rules shipped in `gx 0.7.2`** (2026-05-26); the repo pins **`gx 0.8.0`** (2026-05-31), which makes `excessive-permissions` default to `error` (gmeligio/gx#89). Adopting them in this repo's `gx` configuration moves enforcement from review-time to PR-CI, mechanically, every PR.

## What Changes

- **Bump the pinned `gx` version** to `0.8.0` in `mise.toml` (the file that holds the toolchain pin). Run `gx tidy` after the bump; if it changes any output formatting, commit that separately.
- **Add a `[lint.rules]` section** to `.github/gx.toml`. The six rules' default severities under gx 0.8.0 already match what `ci-workflow-hardening` requires (`missing-permissions`/`dangerous-trigger`/`unprotected-secrets`/`excessive-permissions`/`pr-head-checkout` → `error`; `missing-concurrency` → `warn`), so the section only needs the `pr-head-checkout` override that carries the one ignore (below). The rule→requirement mapping is recorded as comments in `gx.toml`.
- **Add one `ignore` entry** for `pr-head-checkout` scoped to `.github/workflows/gx.yml`. Its `tidy` job checks out the PR HEAD ref under a GitHub App token, which the rule flags as the "pwn request" pattern. The job is already fork-gated (`if: github.event.pull_request.head.repo.full_name == github.repository`), so fork PRs never reach the checkout — the finding is a true pattern match but not exploitable here. The `ignore` documents that review decision in config. This is the **only** false positive against the current corpus (verified: with this one ignore and all six rules at error, `gx lint` exits 0).
- **MODIFY `ci-workflow-hardening`** to add a single requirement: the structural properties this spec defines SHALL be enforced by `gx lint` running in CI on every PR, with the corresponding rules set to error-level. This ties human-readable policy to mechanical enforcement so the spec cannot quietly drift from the gate. The rule→requirement mapping is recorded as comments in `.github/gx.toml` (not in any SECURITY.md).
- **No new workflows** — `.github/workflows/gx.yml` already runs `gx lint` on every PR.
- **No new tools** — gx is already pinned, installed in CI via mise, and authoritative for workflow files (Renovate's `github-actions` manager is disabled per `.github/renovate.json:12`).
- **Required-status-check wiring is a tracked follow-up on p10.** Making `gx lint` a *required* check needs `.github/rulesets/main.json`, the ruleset-as-code file p10 introduces. That directory does not exist yet, so this change cannot wire the required check. p10 carries the follow-up: when its ruleset file lands, add the `gx lint` job name to `required_status_checks`.

## Capabilities

### Modified Capabilities

- `ci-workflow-hardening`: gains a single new requirement — "structural properties SHALL be enforced by `gx lint`" — that ties every existing scenario to a concrete enforcement mechanism. No existing scenario is invalidated; this is additive.

### New Capabilities

_None._ Adopting an enforcement mechanism for an existing capability is a modification, not a new capability.

## Impact

- **Affected files**: `mise.toml` (gx version bump → `0.8.0`), `.github/gx.toml` (new `[lint.rules]` section with the one scoped `ignore`), `.github/gx.lock` (only if `gx tidy` re-resolves anything).
- **Explicitly NOT modified**: any `SECURITY.md`. The rule→requirement mapping lives in `.github/gx.toml` comments.
- **Behavioral change for contributors**: a PR that introduces a new workflow without a `permissions:` block, with `pull_request_target`, or with an unguarded `secrets.*` reference will fail CI on the `gx lint` check. Previously such PRs would pass CI and rely on review.
- **Behavioral change for the maintainer**: the `ci-workflow-hardening` spec's structural rules are now mechanically enforced rather than mentally tracked during review. The maintainer can focus review attention on intent rather than checklist items.
- **Risk — false positives**: only one is known (`gx.yml` `pr-head-checkout`, handled by the scoped `ignore`). Each rule supports `level = "off"` and per-target `ignore = [...]` entries in `gx.toml` if more surface later.
- **Cross-change dependency on p10**: p10's proposal adds `.github/workflows/auto-approve-bots.yml` on a `pull_request_target` trigger. The `dangerous-trigger` rule (error) this change enables will block that workflow. **p10 SHALL add its own `dangerous-trigger` ignore** for `auto-approve-bots.yml` (justified: that workflow does no `actions/checkout` of PR contents) when it lands. This change documents the dependency; p10 owns the ignore.
- **Depends on**:
  - `p7-harden-workflow-permissions` archived (its `ci-workflow-hardening` spec is what this change modifies). ✅ archived.
  - `gmeligio/gx#87` released. ✅ shipped in `gx 0.7.2`; repo pins `gx 0.8.0`.
  - `p10-strengthen-branch-protection` for the required-status-check wiring (soft dependency — the required-check edit is a follow-up tracked on p10, not part of this change).
- **Out of scope**: actionlint-style correctness rules (expression syntax, runner labels, deprecated commands) — deferred to a future gx change. Shell-script linting via shellcheck — same. Composite-action extraction for the workflow prologue — abandoned in favor of mechanical enforcement; see "Why" above. Any SECURITY.md edits — explicitly excluded.
