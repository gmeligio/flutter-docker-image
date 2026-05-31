## 1. Bump the pinned gx version

- [x] 1.1 Update the `gx` pin in `mise.toml` from `0.7.1` to `0.7.2` (`"github:gmeligio/gx" = "0.7.2"`). (Pin lives in repo-root `mise.toml`, not `.config/mise/config.toml`.)
- [x] 1.2 Run `mise install` locally; confirm `gx --version` reports `0.7.2`. (`mise exec -- gx --version` → `gx 0.7.2`.)
- [x] 1.3 Run `gx tidy` locally; if any workflow file or `.github/gx.lock` changes (e.g., comment formatting, re-resolution), commit the result as a separate "chore(deps): gx tidy after version bump" commit. (`gx tidy` → "Up to date"; no drift, no separate commit.)

## 2. Configure the new rules in `.github/gx.toml`

- [x] 2.1 Add a `[lint.rules]` section with explicit entries for the six workflow-security rules. Set severities: `missing-permissions = { level = "error" }`, `dangerous-trigger = { level = "error" }`, `unprotected-secrets = { level = "error" }`, `pr-head-checkout` at `error` with the scoped ignore (task 2.2), `excessive-permissions = { level = "warn" }`, `missing-concurrency = { level = "warn" }`. Add a comment above each entry naming the `ci-workflow-hardening` requirement it enforces (the rule→requirement mapping lives here, NOT in any SECURITY.md).
- [x] 2.2 Add the one known scoped ignore for the repo's own gx workflow:
  ```toml
  pr-head-checkout = { level = "error", ignore = [
      # gx.yml's `tidy` job checks out PR HEAD under an App token but is
      # fork-gated (head.repo.full_name == github.repository), so the
      # "pwn request" pattern is not reachable from forks.
      { workflow = ".github/workflows/gx.yml" },
  ] }
  ```
  Use the `workflow` key (and `job`/`step` if ever needed) — never `action`, which is meaningless for workflow-security rules and breaks the match.
- [x] 2.3 Run `gx lint` locally. Expect exit 0 (the corpus passes all six rules with the single ignore above). If any *new* diagnostic appears:
  - True positive → fix the workflow.
  - True-pattern-but-fork-gated → add a narrowly-scoped `ignore` with a comment naming why.
- [x] 2.4 Re-run `gx lint`; confirm it exits 0. (Exit 0 — "No lint issues found".)

## 3. Verify the gate actually bites (negative test)

- [x] 3.1 On a throwaway local branch, introduce a deliberate violation (e.g., remove the top-level `permissions:` block from one workflow). (Temporarily removed it from `changelog.yml`, restored via `git checkout`.)
- [x] 3.2 Run `gx lint`; confirm it exits non-zero with the expected diagnostic (`missing-permissions`). Discard the branch — this proves the rules fire, not just that the corpus happens to pass. (Exit 1 with `missing-permissions`; restored → exit 0.)

## 4. Update the spec

- [x] 4.1 Confirm the spec delta (`specs/ci-workflow-hardening/spec.md`) reflects mechanical enforcement with the rule→requirement mapping in `gx.toml` (no SECURITY.md). The archive flow applies this delta to the main spec. (Spec mandates mapping in gx.toml comments; gx.toml carries them. Verified aligned.)

## 5. Verify in CI

- [x] 5.1 Open a real PR with the gx bump + `gx.toml` config. Confirm CI runs `gx lint` (`.github/workflows/gx.yml`'s `lint` job) and it passes against the corpus. (Draft PR #476; `lint` job passed in 24s, all checks green.)
- [x] 5.2 After merge, confirm Scorecard does not regress on `TokenPermissionsID` or `BinaryArtifacts` on the next cycle. (Confirmed: no Scorecard regression.)

## 6. Hand off the cross-change follow-ups

- [x] 6.1 Record on p10's tracker: when `.github/rulesets/main.json` is created, add the `gx lint` job name to `required_status_checks` so the gate becomes a *required* check (it is advisory until then). (Added as p10 tasks.md task 6.1.)
- [x] 6.2 Record on p10's tracker: `auto-approve-bots.yml` (p10's `pull_request_target` workflow) MUST get its own scoped `dangerous-trigger` ignore in `.github/gx.toml` when p10 lands, with a comment naming the reviewed threat model (the workflow does no `actions/checkout` of PR contents). (Added as p10 tasks.md task 6.2.)

## 7. Archive

- [ ] 7.1 Archive this change via `/opsx:archive p8-enforce-workflow-policy-via-gx` once CI is green.
