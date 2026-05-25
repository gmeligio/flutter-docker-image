## ADDED Requirements

### Requirement: The active ruleset is versioned as code

The contents of the active GitHub Ruleset for `~DEFAULT_BRANCH` SHALL be checked into `.github/rulesets/main.json` in the shape accepted by `PUT /repos/{owner}/{repo}/rulesets/{id}`. A sibling `.github/rulesets/README.md` SHALL document (a) the apply command, (b) the rule that ruleset edits go through PR review, (c) the deliberate choice of `required_approving_review_count: 0` for solo-maintainer reasons with a link to the proposal that decided it.

The experience context is the maintainer auditing the rules months later, recovering from an accidental UI edit, or replicating the rules to a fork — the JSON is the single source of truth, even though GitHub does not yet apply rulesets from a repo file automatically.

#### Scenario: The maintainer needs to know the rules at a past commit

- **GIVEN** a maintainer needs to know what ruleset was active on a given date
- **WHEN** they run `git show <commit>:.github/rulesets/main.json`
- **THEN** the file echoes the rules at that commit
- **AND** drift between the file and the live ruleset is detectable via `gh api … rulesets/1959230 | diff - .github/rulesets/main.json`

#### Scenario: A ruleset edit is proposed via PR

- **GIVEN** a PR changes `.github/rulesets/main.json`
- **WHEN** the PR is reviewed
- **THEN** the diff is the only signal of the intended change
- **AND** the PR description states whether the live ruleset has been applied yet (apply is out-of-band; not automated by GitHub)

### Requirement: `gx lint` is a required status check on the default branch

The active ruleset SHALL list the `gx lint` job (exposed by `.github/workflows/gx.yml`) as a required status check. The check SHALL pass before a PR is allowed to merge into the default branch. After `p8-enforce-workflow-policy-via-gx` archives, this single required check covers both action-pinning hygiene and the structural workflow properties mandated by `ci-workflow-hardening`.

The experience context is the maintainer trusting that "all green = mergeable" — the structural requirements in `ci-workflow-hardening` are mechanically gated by `gx lint`, not by remembered checklists. A PR cannot merge with a missing top-level `permissions:` block, an unguarded fork-PR secret reference, an unreviewed `pull_request_target`, or an unpinned action, because the required check will fail.

#### Scenario: A PR with a failing `gx lint` is opened

- **GIVEN** a PR introduces a workflow that triggers any error-level `gx lint` diagnostic
- **WHEN** CI runs
- **THEN** the `gx lint` check reports failure on the PR
- **AND** the ruleset blocks the merge regardless of any approvals

#### Scenario: The `gx lint` job is renamed

- **GIVEN** a future change renames the `gx lint` job (e.g. p9 reorganizes `gx.yml`)
- **WHEN** the rename PR is opened
- **THEN** `.github/rulesets/main.json` is updated in the same PR to track the new job name
- **AND** the live ruleset is re-applied via `gh api -X PUT` as part of the rollout (recorded in the change's tasks.md)

### Requirement: The ruleset's bypass actors are explicit, justified, and minimal

The `bypass_actors` array in the active ruleset SHALL contain only entries whose purpose is documented in `.github/rulesets/README.md`. Each entry SHALL use the narrowest `bypass_mode` compatible with its purpose (`pull_request` whenever the App's writes go through a PR; `always` only when the App pushes directly).

The experience context is the Scorecard grader checking `BranchProtectionID`'s *"applies to administrators is disabled"* warning — every bypass entry is a documented exception, not an unexplained loophole. The maintainer can audit the list in seconds.

#### Scenario: A bypass entry exists and is needed

- **GIVEN** the active ruleset has a `bypass_actors` entry for the `verified-commit` App used by `changelog.yml`/`tag.yml`
- **WHEN** the entry is reviewed
- **THEN** `.github/rulesets/README.md` names the App, names the workflows that depend on it, and justifies the chosen `bypass_mode`

#### Scenario: A bypass entry exists and is no longer needed

- **GIVEN** a `bypass_actors` entry's App is no longer used by any workflow
- **WHEN** the audit task runs
- **THEN** the entry is removed from the live ruleset and from `.github/rulesets/main.json`
- **AND** the next Scorecard scan reflects the change

### Requirement: Trusted bot PRs are auto-approved by a hard-coded allowlist workflow

The repository SHALL include `.github/workflows/auto-approve-bots.yml` that, for PRs opened by an explicit allowlist of bot authors AND whose changed files are entirely within an explicit allowlist of paths, posts an `APPROVE` review via the existing `VERIFIED_COMMIT_ID`/`VERIFIED_COMMIT_KEY` GitHub App token. The workflow SHALL NOT `actions/checkout` PR contents. Both allowlists SHALL be hard-coded in the workflow body so that any change goes through PR review.

The experience context is the maintainer who wants Renovate's lockfile bumps to merge promptly without manual click-through, AND wants every approval decision to be auditable in the workflow run log. PRs that fall outside either allowlist halt for human review — fail closed, not open.

#### Scenario: A Renovate PR touches only allowlisted paths

- **GIVEN** Renovate opens a PR that touches only `pnpm-lock.yaml`
- **WHEN** `auto-approve-bots.yml` runs
- **THEN** the workflow posts an APPROVE review within ~30 s
- **AND** the run summary records `author=renovate[bot] paths=pnpm-lock.yaml decision=APPROVE`

#### Scenario: A Renovate PR touches a non-allowlisted path

- **GIVEN** a bot PR touches `pnpm-lock.yaml` AND `src/foo.ts`
- **WHEN** the workflow runs
- **THEN** the workflow does NOT post an approval
- **AND** the run summary records `decision=SKIP reason=path 'src/foo.ts' not in allowlist`
- **AND** the PR stays gated for human review

#### Scenario: A PR is opened by an account outside the author allowlist

- **GIVEN** a PR is opened by an account not in the author allowlist
- **WHEN** the workflow runs
- **THEN** the workflow does NOT post an approval
- **AND** the run summary records `decision=SKIP reason=author not in allowlist`

#### Scenario: The auto-approve workflow itself is the attack target

- **GIVEN** the threat model in the change proposal — `pull_request_target` is used, but `actions/checkout` is NOT
- **WHEN** a malicious PR attempts to inject code into the workflow's execution
- **THEN** the workflow runs the version on `main`, not the PR's version (`pull_request_target` semantics)
- **AND** the workflow's only PR-derived inputs (`user.login`, changed file paths) are compared against hard-coded allowlists, not interpolated into shell commands

### Requirement: The Scorecard `CodeReviewID` finding is accepted as a solo-maintainer ceiling

Because GitHub does not allow self-approval and this repo has a sole maintainer, the Scorecard `CodeReviewID` check (which measures the fraction of approved changesets in the rolling 30-PR window) SHALL NOT be treated as a fixable finding. `.github/SECURITY.md` SHALL document this acceptance, the recovery path (onboarding a co-maintainer), and SHALL link to the change proposal that decided it.

The experience context is the auditor or new contributor who reads the Scorecard dashboard, sees a high-severity score of 0–3, and would otherwise flag it as a neglected security gap. The SECURITY.md note redirects them to the documented rationale instead, so the finding doesn't generate repeated re-discovery cycles.

#### Scenario: A new contributor or auditor sees the low CodeReview score

- **GIVEN** an external reader inspects the Scorecard alerts
- **WHEN** they encounter `CodeReviewID` at a low score
- **THEN** `.github/SECURITY.md` (linked from the repo root) explains the solo-maintainer constraint
- **AND** the explanation names what would change if a co-maintainer joins

#### Scenario: Required-approval policy is reconsidered

- **GIVEN** a co-maintainer is onboarded
- **WHEN** the governance is revisited
- **THEN** a new change proposal is opened to raise `required_approving_review_count` to `1` and `require_last_push_approval` to `true`
- **AND** `.github/SECURITY.md` and `.github/rulesets/main.json` are updated in the same change
