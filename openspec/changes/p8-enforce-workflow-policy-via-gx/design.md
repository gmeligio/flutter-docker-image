## Context

`ci-workflow-hardening` (from p7) defines structural security properties for every workflow under `.github/workflows/`, but enforces them only through maintainer review. `gx` already runs in CI via `.github/workflows/gx.yml` (`gx lint`), checking *action hygiene* (SHA pinning, manifest sync). As of `gx 0.7.2`, `gx lint` also ships six *workflow-security* rules that cover exactly the structural properties the spec mandates. This change wires those rules on, turning review-time policy into a CI gate.

The repo pins `gx 0.8.0` in `mise.toml`. The 11-workflow corpus has been verified against `gx 0.8.0`: relying on default severities (with one scoped `pr-head-checkout` ignore), `gx lint` exits 0. gx 0.8.0's breaking change makes `excessive-permissions` default to `error`; the corpus already satisfies it.

## Goals / Non-Goals

**Goals:**

- Enable the six workflow-security rules in `.github/gx.toml` at the severities the spec requires.
- Bump the pinned `gx` to `0.8.0`, the release that ships the rules.
- Keep the rule→requirement mapping auditable from this repo (as `gx.toml` comments).
- Land with `gx lint` green on the existing corpus.

**Non-Goals:**

- Modifying any `SECURITY.md` file (explicitly excluded).
- Making `gx lint` a *required* status check — that needs `.github/rulesets/main.json` (p10's file, not yet created); tracked as a p10 follow-up.
- actionlint/shellcheck-style correctness linting.
- Composite-action extraction (abandoned approach; see proposal).

## Decisions

**Rely on gx 0.8.0 defaults; override only `pr-head-checkout`.** gx 0.8.0's built-in defaults set the six rules to the severities we want (`missing-permissions`/`dangerous-trigger`/`unprotected-secrets`/`excessive-permissions`/`pr-head-checkout` → `error`, `missing-concurrency` → `warn`). The `[lint.rules]` block carries only the `pr-head-checkout` entry, because it needs the `gx.yml` `ignore` — a default can't express that. The rule→requirement mapping still lives in `gx.toml` comments for auditability. Pinning the gx version (and the spec's "pin only rises" rule) guards against a default silently weakening on an upstream change.

**Scope the one false positive with `ignore`, not `level = "off"`.** `gx.yml`'s `tidy` job checks out PR HEAD under an App token; `pr-head-checkout` flags it. The job is fork-gated, so it's not exploitable. We exempt that one workflow with `pr-head-checkout = { level = "error", ignore = [{ workflow = ".github/workflows/gx.yml" }] }` rather than disabling the rule, so the rule keeps protecting every other workflow. The `ignore` uses the `workflow` key (for workflow-security rules the `action` key is meaningless and would break the match, per gx `docs/lint-rules.md`).

**Severities.** Under gx 0.8.0 defaults: `missing-permissions`, `dangerous-trigger`, `pr-head-checkout`, `unprotected-secrets`, `excessive-permissions` → `error` (the load-bearing "pwn request" / least-privilege gates); `missing-concurrency` → `warn` (hygiene; the corpus passes it at `error` too). `excessive-permissions` moved to error-by-default in gx 0.8.0 (gmeligio/gx#89) — a free tightening for us since the corpus already complies.

**Required-check wiring deferred to p10.** `.github/rulesets/` does not exist. The required-status-check edit is one line once p10 creates `main.json`; forcing it here would mean creating p10's file out of band. Recorded as a p10 follow-up instead.

## Risks / Trade-offs

- **A second false positive appears on a future workflow** → each rule supports scoped `ignore` (workflow/job keys); the spec requires a naming comment, so exemptions stay reviewable.
- **gx version drift downgrades below 0.8.0** → spec scenario requires the pin only ever rise; a downgrade PR is rejected in review. Renovate's `github-actions` manager is already disabled, limiting automated downgrades.
- **p10 forgets the `dangerous-trigger` ignore for `auto-approve-bots.yml`** → that workflow would fail `gx lint` once both changes land. Mitigation: the dependency is documented in this proposal's Impact and is a task on p10.
- **Enforcement is advisory until p10 wires the required check** → `gx lint` failures show on the PR but don't block merge until then. Accepted: visible CI failure is already a strong signal for a solo maintainer.

## Migration Plan

1. Bump pin → `0.8.0`; `mise install` (with `GITHUB_TOKEN`); confirm `gx --version`.
2. `gx tidy`; commit any formatting drift separately.
3. Add `[lint.rules]` + the one `ignore` to `.github/gx.toml`.
4. `gx lint` locally → expect exit 0.
5. Open PR; CI `gx lint` runs and passes.
6. Rollback: revert the `gx.toml` and pin changes — no runtime artifact, no data migration, fully reversible in one revert commit.

## Automated Test Strategy

The change *is* test infrastructure — `gx lint` in CI is the test. Verification levels:

- **Local pre-PR**: run `gx 0.8.0 lint` against the full corpus; success criterion is exit 0 (errors silenced, warnings acceptable). Verified.
- **Negative test**: temporarily introduce a violation in a throwaway branch (e.g. remove a `permissions:` block) and confirm `gx lint` exits non-zero with the expected diagnostic — proves the gate actually bites, not just that the corpus happens to pass.
- **CI**: `.github/workflows/gx.yml`'s `lint` job runs `gx lint` on every PR touching workflow files. No new test infra; the existing job gains coverage automatically once the rules are configured.

Critical path: the `gx.toml` `[lint.rules]` block + the `pr-head-checkout` ignore. If either is wrong, CI either blocks legitimate PRs (over-strict) or passes violations (under-strict). Both are caught by the local run + negative test above.

## Observability

- **Failure surfacing**: `gx lint` failures appear as a failed CI check on the PR with a per-rule diagnostic naming the file, job, and step (verified output format during research). Not silent.
- **Log artifact**: `gx lint` writes a timestamped log (e.g. `/tmp/.../gx/lint/<ts>.log`) and prints its path, so a maintainer can inspect the full diagnostic set beyond the summary line.
- **Silent-failure risk**: the one way enforcement could go silently weak is a gx downgrade below the rules-bearing release (rules absent → lint passes vacuously). The spec's "pin only rises" scenario and disabled Renovate actions-manager guard against it; a downgrade is visible as a diff to `mise.toml` in review.

## Open Questions

- `excessive-permissions` is now `error` by default (resolved by the gx 0.8.0 upgrade — gmeligio/gx#89). `missing-concurrency` stays `warn` (hygiene); raising it to `error` is a free future tightening since the corpus already passes it.
