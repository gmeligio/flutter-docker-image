# ci-repo-governance Specification

## Purpose

Define how changes reach the default branch so the protected branch's history reflects only reviewed-or-gated changes. Every write to `~DEFAULT_BRANCH` — including automated changelog updates and regenerated documentation — SHALL flow through a pull request subject to the branch ruleset, the ruleset SHALL have no bypass actor, and trusted automated PRs SHALL auto-merge on passing checks. The experience context is the maintainer (and auditor / Scorecard) trusting there is no side channel by which a workflow mutates `main` without passing the same checks a human PR passes.

## Requirements

### Requirement: All writes to the default branch go through a pull request

No workflow SHALL push commits directly to `~DEFAULT_BRANCH`. Every change that lands on the default branch — including automated changelog updates and regenerated documentation — SHALL arrive via a pull request that is subject to the branch ruleset (required status checks, signatures, linear history, CODEOWNERS review).

The experience context is the maintainer trusting that the protected branch's history reflects only reviewed-or-gated changes: there is no side channel by which a workflow mutates `main` without passing the same checks a human PR passes.

#### Scenario: A version bump carries its changelog

- **GIVEN** `update-version.yml` detects a newer Flutter version
- **WHEN** it opens the version-bump pull request
- **THEN** the regenerated `changelog.md` for the new version is part of that same PR
- **AND** the version change and its changelog reach `main` together, only after the PR's required checks pass and it is merged
- **AND** no commit is pushed directly to `main`

#### Scenario: A release is tagged from the merged version

- **GIVEN** a version-bump PR merges, changing `config/version.json` on `main`
- **WHEN** `prepare-release.yml` runs
- **THEN** it creates the version tag from the merged commit without pushing any commit
- **AND** the tag push triggers `release.yml`

#### Scenario: A same-repo PR edits documentation source

- **GIVEN** a same-repo pull request (maintainer or `renovate[bot]`) changes a docs generator source (`docs/build.mjs`, `docs/examples.cue`, or `config/version.json`)
- **WHEN** `update-docs.yml` runs
- **THEN** the `generate` job regenerates the committed docs output and pushes it onto the same PR branch
- **AND** that push re-triggers the `check` job, which then passes
- **AND** the regenerated output is reviewed in the same PR; no commit is pushed directly to `main`

#### Scenario: A fork PR leaves documentation output stale

- **GIVEN** a pull request from a fork changes a docs generator source (`docs/build.mjs`, `docs/examples.cue`, or `config/version.json`) without regenerating the output
- **WHEN** `update-docs.yml` runs
- **THEN** the `generate` job is skipped (no secret reaches fork code)
- **AND** the `check` job fails with an explicit instruction to run the docs build and commit the result
- **AND** the PR cannot merge until the contributor commits the regenerated output

#### Scenario: Documentation output is already in sync

- **GIVEN** a pull request whose docs generator source change produces no output diff
- **WHEN** `update-docs.yml` runs
- **THEN** the `check` job passes and `generate` pushes nothing
- **AND** the workflow does not re-trigger itself

### Requirement: The default-branch ruleset has no bypass actor

The active ruleset for `~DEFAULT_BRANCH` SHALL NOT define any `bypass_actors`. Because every write now flows through a PR, no App or actor needs to bypass the rules. The ruleset is managed as code outside this repository; this requirement is the in-repo contract that the workflows here do not depend on a bypass existing.

The experience context is the auditor (or Scorecard's `EnforceAdmins` check) confirming the protected branch has no unexplained loophole — the bypass list is empty, and no workflow regresses by reintroducing a direct push that would require one.

#### Scenario: A workflow attempts a direct push to main

- **GIVEN** the ruleset has no bypass actor
- **WHEN** any workflow attempts to push a commit directly to `main`
- **THEN** the push is rejected by the ruleset
- **AND** the only way to land the change is through a pull request

#### Scenario: Tag creation is unaffected by bypass removal

- **GIVEN** the ruleset targets `~DEFAULT_BRANCH` (branches), not tags
- **WHEN** `prepare-release.yml` creates a version tag via the GitHub API (`refs/tags/*`)
- **THEN** the tag is created successfully without any bypass actor
- **AND** the tag push still triggers `release.yml`

### Requirement: Trusted automated pull requests auto-merge once every merge requirement is met

Every pull request opened by trusted automation — Renovate, and the version-bump PR opened by `update-version.yml` — SHALL have GitHub-native auto-merge enabled at the moment the pull request is opened or updated, requesting the `squash` method the ruleset allows. The pull request SHALL then merge with no further manual action once, and only once, every merge requirement the `~DEFAULT_BRANCH` ruleset imposes is satisfied.

Those requirements include an approving review from a code owner: the ruleset sets `require_code_owner_review: true` and `CODEOWNERS` covers every path, so an automation-authored pull request cannot merge until the maintainer approves it. **Enabling auto-merge therefore does not mean merging on green — it means the maintainer's approval is the act that merges.** The ruleset SHALL keep `require_code_owner_review: true` while auto-merge is enabled at open time; that setting is the only human gate on an unattended weekly commit to the default branch, and relaxing it would silently convert every automation pull request into a merge-on-green. At least one required status check SHALL remain configured, so auto-merge cannot merge a pull request whose checks are absent or failing.

**Experience context:** the maintainer reviews an automated dependency or version bump and expects the approval to be the end of their involvement. Before this, approval and merge were two separate actions on the same pull request, and only one of them was automated — Renovate's pull requests merged two seconds after approval while the version-bump pull request sat green and approved until it was clicked. The gap is not just the click: an approval given without a follow-up leaves the release chain stalled with nothing indicating it. Enforcement stays entirely with GitHub, so no automation can merge something the maintainer has not approved, and no check is bypassed to make it happen.

#### Scenario: A version-bump pull request waits for review

- **GIVEN** `update-version.yml` opens the version-bump pull request with auto-merge enabled
- **WHEN** all required status checks pass and no review has been submitted
- **THEN** the pull request does NOT merge
- **AND** it stays open awaiting the code owner's approval

#### Scenario: The code owner approves an automation pull request

- **GIVEN** an automation pull request with auto-merge enabled and all required checks green
- **WHEN** the code owner submits an approving review
- **THEN** GitHub squash-merges the pull request without any further manual action
- **AND** the maintainer's only action on the pull request was the approval

#### Scenario: A required check fails

- **GIVEN** an automation pull request with auto-merge enabled
- **WHEN** any required status check fails, or a required check never reports
- **THEN** GitHub does NOT merge the pull request, approved or not
- **AND** it stays open for the maintainer's attention

#### Scenario: The approval is dismissed by a later push

- **GIVEN** an approved automation pull request with auto-merge enabled
- **WHEN** a commit is pushed to its branch, dismissing the stale review
- **THEN** the pull request does NOT merge
- **AND** it merges only after the code owner approves the new head

#### Scenario: Auto-merge cannot be enabled

- **GIVEN** `update-version.yml` has opened the version-bump pull request
- **WHEN** the call enabling auto-merge fails for any reason
- **THEN** the workflow run does NOT fail and the pull request is still opened with its changelog
- **AND** the failure is reported as a warning in the run log
- **AND** the maintainer can review and merge the pull request manually, as before

### Requirement: An automation pull request behind the default branch is brought up to date

Because the `~DEFAULT_BRANCH` ruleset sets `strict_required_status_checks_policy: true`, a pull request whose branch is behind `main` cannot merge even with every check green and the code owner's approval recorded. GitHub's auto-merge does not update the branch; it waits indefinitely and reports nothing. When trusted automation opens or updates a pull request, it SHALL detect that the branch is behind the default branch and request an update, so the branch is current before the maintainer reviews it. The update SHALL be attempted before approval, never after: `dismiss_stale_reviews_on_push: true` means a branch update following an approval dismisses that approval. A failed update SHALL be reported as a warning and SHALL NOT fail the run, leaving today's manual "Update branch" as the fallback.

**Experience context:** the maintainer approves an automated bump and treats the approval as the end of their involvement. Before auto-merge, the merge click surfaced a stale branch — GitHub blocks the button and names the reason. Automating the click removes that moment, so a stale branch becomes a pull request that is approved, green, and silently unmerged, with the release for that Flutter version never published. This is not hypothetical: `update-version.yml` and Renovate both run in the same early-morning window, so any Renovate merge landing between the bump pull request opening and the maintainer's approval leaves the bump behind.

#### Scenario: The bump pull request falls behind main before review

- **GIVEN** a version-bump pull request with auto-merge enabled
- **AND** another pull request merges to `main` afterwards, leaving the bump branch behind
- **WHEN** the automation next runs for that pull request
- **THEN** it requests an update of the pull request branch from `main`
- **AND** the required checks re-run against the updated branch
- **AND** the maintainer's approval merges it, because the branch is no longer stale

#### Scenario: The branch is already current

- **GIVEN** a version-bump pull request whose branch already contains the tip of `main`
- **WHEN** the automation evaluates whether an update is needed
- **THEN** no update is requested and no commit is pushed
- **AND** no approval is dismissed

#### Scenario: The branch update cannot be performed

- **GIVEN** a version-bump pull request behind `main`
- **WHEN** the update request fails, for example because the branch has a conflict
- **THEN** the workflow run does NOT fail
- **AND** the failure is reported as a warning in the run log
- **AND** the maintainer can update and merge the pull request manually, as before

### Requirement: An automated merge triggers the release chain

The identity that performs an automated merge into `~DEFAULT_BRANCH` SHALL be one whose pushes trigger workflow runs — a GitHub App installation token, not the workflow's own `GITHUB_TOKEN`, whose pushes GitHub suppresses from triggering further workflows. Because GitHub attributes an auto-merge to whichever identity enabled it, this constrains the token used to enable auto-merge, not only the token used to push.

**Experience context:** a CI engineer waiting on the image for a new Flutter release sees it published because merging the version bump creates the tag, and the tag runs the release. `prepare-release.yml` triggers on a push to `main` touching `config/version.json`; if the merge that lands that file is suppressed from triggering workflows, no tag is created, `release.yml` never runs, and no image is published for the new version — while the pull request shows as merged and everything looks correct. Automating the merge is what makes this reachable: a human's merge always triggered the chain.

#### Scenario: An auto-merged version bump produces a release

- **GIVEN** a version-bump pull request whose auto-merge was enabled with a GitHub App installation token
- **WHEN** the code owner approves and GitHub merges it
- **THEN** the push to `main` triggers `prepare-release.yml`, which creates the version tag
- **AND** the tag triggers `release.yml`, which publishes the image for the new version

### Requirement: Renovate's operating mode is declared in the repository

`.github/renovate.json` SHALL set `"mode": "full"`. The hosted Renovate app injects `mode=silent` as global configuration; `mode` is a repository-level option merged after global config, so the in-repo value overrides it. This requirement is the in-repo contract that Renovate's output is observable — the setting itself is administered outside this repository, and without an in-repo declaration a portal toggle can disable every guarantee the other Renovate requirements make, invisibly to code review.

The experience context is the maintainer who expects a stale dependency to arrive as a pull request. Under `mode=silent` Renovate still computes updates and then discards them: no PRs, no branches, no Dependency Dashboard. A dependency that stops resolving is recorded internally but only ever rendered into a dashboard or PR body, so silent mode makes the failure structurally unreachable and it surfaces as nothing happening at all. This is how the `openjdk-17-jdk-headless` pin went unmaintained for ten weeks and then broke the image build on `main`. Note also that `mode=silent` composes with `automerge` into "changes merge without producing a PR trail" — a property neither setting reveals on its own.

#### Scenario: A dependency update is available

- **GIVEN** `.github/renovate.json` sets `"mode": "full"`
- **WHEN** Renovate finds an update on its weekly schedule
- **THEN** it creates the branch and opens a pull request
- **AND** the update is visible without anyone reading a job log

#### Scenario: A pinned dependency stops resolving

- **GIVEN** a pin whose lookup returns no result
- **WHEN** Renovate runs
- **THEN** the failure is reported on the Dependency Dashboard issue
- **AND** the maintainer learns of it before the next image build fails

#### Scenario: The hosted app sets a conflicting mode

- **GIVEN** the hosted app injects `mode=silent` as global configuration
- **WHEN** Renovate resolves configuration for this repository
- **THEN** the repository's `"mode": "full"` takes precedence
- **AND** the job log does not report `Repository is running with mode=silent`
</content>
</invoke>
