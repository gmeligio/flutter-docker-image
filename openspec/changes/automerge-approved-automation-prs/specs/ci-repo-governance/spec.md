## MODIFIED Requirements

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

### Requirement: An automated merge triggers the release chain

The identity that performs an automated merge into `~DEFAULT_BRANCH` SHALL be one whose pushes trigger workflow runs — a GitHub App installation token, not the workflow's own `GITHUB_TOKEN`, whose pushes GitHub suppresses from triggering further workflows. Because GitHub attributes an auto-merge to whichever identity enabled it, this constrains the token used to enable auto-merge, not only the token used to push.

**Experience context:** a CI engineer waiting on the image for a new Flutter release sees it published because merging the version bump creates the tag, and the tag runs the release. `prepare-release.yml` triggers on a push to `main` touching `config/version.json`; if the merge that lands that file is suppressed from triggering workflows, no tag is created, `release.yml` never runs, and no image is published for the new version — while the pull request shows as merged and everything looks correct. Automating the merge is what makes this reachable: a human's merge always triggered the chain.

#### Scenario: An auto-merged version bump produces a release

- **GIVEN** a version-bump pull request whose auto-merge was enabled with a GitHub App installation token
- **WHEN** the code owner approves and GitHub merges it
- **THEN** the push to `main` triggers `prepare-release.yml`, which creates the version tag
- **AND** the tag triggers `release.yml`, which publishes the image for the new version
