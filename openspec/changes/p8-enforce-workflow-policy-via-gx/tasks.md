## 1. Wait for the upstream gx release

- [ ] 1.1 Confirm `gmeligio/gx` has shipped a release that includes the rules from `add-workflow-security-rules`. Cross-reference the `gx --version` output against the gx CHANGELOG.
- [ ] 1.2 If the release is not yet available, pause this change — do NOT implement the items below against a pre-release build.

## 2. Bump the pinned gx version

- [ ] 2.1 Update the `gx` pin in `.config/mise/config.toml` (or whichever file holds the mise toolchain pin — verify via `mise current`).
- [ ] 2.2 Run `mise install` locally; confirm `gx --version` reports the new version.
- [ ] 2.3 Run `gx tidy` locally; if any workflow file changes (e.g., updated comment formatting), commit the result as a separate "chore(deps): gx tidy after version bump" commit.

## 3. Configure the new rules in `.github/gx.toml`

- [ ] 3.1 Add a `[lint.rules]` section with explicit entries for each of the six new rules. Set severities to match `ci-workflow-hardening`: `missing-permissions = { level = "error" }`, `dangerous-trigger = { level = "error" }`, `pr-head-checkout = { level = "error" }`, `unprotected-secrets = { level = "error" }`, `excessive-permissions = { level = "warn" }`, `missing-concurrency = { level = "warn" }`.
- [ ] 3.2 Run `gx lint` locally against the current workflow corpus. Triage every diagnostic:
  - True positives → fix the workflow (out of scope here only if the fix is non-trivial; record as a follow-up).
  - False positives → add a narrowly-scoped `ignore` entry with a comment naming why.
- [ ] 3.3 Re-run `gx lint`; confirm it exits 0 (errors silenced, warnings acceptable).

## 4. Extend `.github/workflows/SECURITY.md`

- [ ] 4.1 Add a section "Mechanical enforcement" listing each `ci-workflow-hardening` structural requirement and the gx rule that enforces it. Format as a small table.
- [ ] 4.2 State the rule: "If `gx lint` passes, the structural properties in `ci-workflow-hardening` hold."
- [ ] 4.3 Link to `.github/gx.toml` and to the gx project for the rule reference docs.

## 5. Wire `gx lint` as a required status check

- [ ] 5.1 Confirm `.github/workflows/gx.yml`'s `gx lint` job has a stable `name:` field. Note the job name (it will become the required-check ID in the ruleset).
- [ ] 5.2 If p10 has archived: add the job name to `.github/rulesets/main.json` under `required_status_checks`; apply via `gh api -X PUT`. If p10 has not yet archived: record this as a follow-up task on p10's tracker so the check gets wired when the ruleset-as-code file is created.
- [ ] 5.3 Open a draft PR that intentionally introduces a violation (e.g., remove the top-level `permissions:` block from a sandbox workflow); confirm the PR is blocked by the failing `gx lint` check.

## 6. Update the spec

- [ ] 6.1 Apply this change's spec delta (`specs/ci-workflow-hardening/spec.md`) to the archived spec via `openspec apply p8-enforce-workflow-policy-via-gx`.
- [ ] 6.2 Confirm `openspec list --json` reports zero unarchived changes that conflict.

## 7. Verify

- [ ] 7.1 Open a real PR with the gx bump + config + SECURITY.md edits. Confirm CI runs `gx lint` and it passes against the post-fix workflow corpus.
- [ ] 7.2 After merge, wait for the next Renovate / Scorecard cycle. Confirm Scorecard does not regress on `TokenPermissionsID` or `BinaryArtifacts`.
- [ ] 7.3 Archive this change via `openspec archive p8-enforce-workflow-policy-via-gx` once verified.
