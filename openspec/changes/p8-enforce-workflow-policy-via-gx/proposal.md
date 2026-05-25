## Why

p7 (`ci-workflow-hardening`) defines the structural properties every workflow under `.github/workflows/` SHALL meet: top-level `permissions:`, `concurrency:` on push/schedule triggers, SHA-pinned actions, no unreviewed `pull_request_target`, fork-secret gates on PR-triggered workflows. Today those properties are enforced **by maintainer review**. A new workflow that omits a `permissions:` block, or a contributor PR that references `secrets.*` without a fork gate, depends on the reviewer remembering the spec.

The previous p8 proposal (`p8-extract-workflow-composites`, deleted in favor of this change) tried to enforce the properties **by abstraction** — funnel every workflow's setup through composite actions that bake in the gates. That approach trades one drift surface (inlined setup steps) for another (composites that callers can simply not use), still requires manual review to catch, and added two new files and a README for ~5 callers — under the break-even point.

The `gx` CLI already runs in this repo's CI (`.github/workflows/gx.yml` calls `gx lint`). The companion change `add-workflow-security-rules` in the `gx` repo adds six workflow-level security rules (`missing-permissions`, `excessive-permissions`, `dangerous-trigger`, `pr-head-checkout`, `missing-concurrency`, `unprotected-secrets`) that together cover the structural properties `ci-workflow-hardening` mandates. Adopting those rules in this repo's `gx` configuration moves enforcement from review-time to PR-CI, mechanically, every PR.

## What Changes

- **Bump the pinned `gx` version** to the release that ships the new rules. Update `.config/mise/config.toml` (or wherever gx is pinned) and re-run `gx tidy` if the new version changes any output formatting.
- **Add a `[lint.rules]` section** to `.github/gx.toml` that explicitly enables the six new rules at the severities `ci-workflow-hardening` requires (most at `error`, `excessive-permissions` and `missing-concurrency` at `warn`). Explicit configuration here is intentional — the gx defaults already match, but writing the levels into the repo's config makes the policy auditable from this repo alone.
- **Extend `.github/workflows/SECURITY.md`** (introduced by p7) with a section "Mechanical enforcement" pointing at `gx lint` and listing which spec requirements each rule enforces. A reviewer who wants to know "does this PR comply with `ci-workflow-hardening`?" reads one line: "yes if `gx lint` passes."
- **MODIFY `ci-workflow-hardening`** to add a single requirement: the structural properties this spec defines SHALL be enforced by `gx lint` running in CI on every PR, with the corresponding rules set to error-level. This ties human-readable policy to mechanical enforcement so the spec cannot quietly drift from the gate.
- **Add `gx lint` to the required-status-checks list in `.github/rulesets/main.json`** — the ruleset-as-code file introduced by p10. (If p10 has not landed yet, this lands as a follow-up after both p10 and the gx release; the proposal documents the dependency explicitly.)
- **No new workflows** — `.github/workflows/gx.yml` already runs `gx lint` on every PR.
- **No new tools** — gx is already pinned, installed in CI via mise, and authoritative for workflow files (Renovate's `github-actions` manager is disabled per `.github/renovate.json:12`).

## Capabilities

### Modified Capabilities

- `ci-workflow-hardening`: gains a single new requirement — "structural properties SHALL be enforced by `gx lint`" — that ties every existing scenario to a concrete enforcement mechanism. No existing scenario is invalidated; this is additive.

### New Capabilities

_None._ Adopting an enforcement mechanism for an existing capability is a modification, not a new capability.

## Impact

- **Affected files**: `.config/mise/config.toml` (gx version bump), `.github/gx.toml` (new `[lint.rules]` section), `.github/workflows/SECURITY.md` (new section), `.github/rulesets/main.json` (added required check; cross-references p10).
- **Behavioral change for contributors**: a PR that introduces a new workflow without a `permissions:` block, with `pull_request_target`, or with an unguarded `secrets.*` reference will fail CI on the `gx lint` check. Previously such PRs would pass CI and rely on review.
- **Behavioral change for the maintainer**: the `ci-workflow-hardening` spec's structural rules are now mechanically enforced rather than mentally tracked during review. The maintainer can focus review attention on intent rather than checklist items.
- **Risk**: false positives on one of the six rules could block legitimate PRs. Each rule supports `level = "off"` and per-target `ignore = [...]` entries in `gx.toml`; the proposal lists no expected false positives against the current workflow corpus (validated locally before opening the PR).
- **Risk**: the `gx` release that ships the new rules has not yet shipped at the time this proposal is written. This change SHALL NOT be implemented until the gx release exists and the new rules can be exercised against this repo's workflow corpus. The dependency is recorded below.
- **Depends on**:
  - `p7-harden-workflow-permissions` archived (its `ci-workflow-hardening` spec is what this change modifies).
  - `gmeligio/gx#add-workflow-security-rules` released — the gx version that includes the six rules must be available as an installable artifact.
  - `p10-strengthen-branch-protection` for the required-status-check wiring (soft dependency — if p10 lands later, that part of this change becomes a follow-up edit to the ruleset file).
- **Out of scope**: actionlint-style correctness rules (expression syntax, runner labels, deprecated commands) — deferred to a future gx change. Shell-script linting via shellcheck — same. Composite-action extraction for the workflow prologue — abandoned in favor of mechanical enforcement; see "Why" above for the rationale.
