## ADDED Requirements

### Requirement: Scheduled sweep prunes untagged versions older than the retention window

A workflow SHALL run on a recurring schedule (no less frequent than weekly) and delete every `ghcr.io/<owner>/flutter-android` package version whose tag list is empty AND whose `created_at` is older than the retention window (default 7 days).

The experience context is the maintainer auditing GHCR storage — they expect the package's version count to converge to roughly the count of currently-tagged versions plus a thin layer of < 7-day-old orphans, not to grow monotonically with PR re-runs.

#### Scenario: Weekly run prunes orphans older than the window

- **GIVEN** the package has 800 untagged versions all created more than 7 days ago, and 50 tagged versions (`pr-*`, `branch-*`, release tags, `buildcache`)
- **WHEN** the scheduled workflow runs
- **THEN** all 800 untagged versions are deleted
- **AND** the 50 tagged versions remain untouched
- **AND** the workflow log contains a per-deletion line `INFO: deleting <id> ... tags=[]` for each deleted version
- **AND** the workflow log contains a summary line naming the deleted count and the remaining count

#### Scenario: Recent orphans are preserved

- **GIVEN** an untagged version created 1 hour ago (orphan from a just-re-run PR build)
- **WHEN** the scheduled workflow runs
- **THEN** that version is NOT deleted
- **AND** the workflow log does not list it as a candidate

### Requirement: Pruning never targets a tagged version

The workflow SHALL filter candidates by the positive invariant `metadata.container.tags == []`. A version with any non-empty tag list — release tag (`<flutter-version>`), handoff tag (`pr-<N>`, `branch-<X>`), buildcache tag, or any future tag — SHALL be unreachable from the delete code path.

The experience context is the maintainer auditing the workflow before merging — they need confidence that this scheduled, unattended job cannot delete a release tag, a `pr-<N>` tag belonging to an open PR, or the `buildcache` tag.

#### Scenario: Release tag is never considered for deletion

- **GIVEN** a release version `3.41.9` (tagged) created more than 7 days ago
- **WHEN** the workflow runs
- **THEN** the `3.41.9` version is not in the candidate list
- **AND** it is not deleted

#### Scenario: Open-PR handoff tag is never considered for deletion

- **GIVEN** PR #500 is open and `pr-500` was last pushed 10 days ago (still tagged on the current manifest)
- **WHEN** the workflow runs
- **THEN** the `pr-500`-tagged version is not in the candidate list

#### Scenario: Buildcache tag is preserved

- **GIVEN** the `buildcache` tag points at a version created more than 7 days ago
- **WHEN** the workflow runs
- **THEN** the tagged buildcache version is preserved
- **AND** older untagged buildcache layer manifests are eligible for deletion

#### Scenario: Tagged-count invariant guards against filter bugs

- **GIVEN** any successful workflow run
- **WHEN** the workflow finishes
- **THEN** the count of tagged versions after pruning equals the count of tagged versions before pruning
- **AND** if the invariant fails, the workflow exits non-zero with a `::error::` annotation naming the count delta

### Requirement: Manual trigger defaults to dry-run

The workflow SHALL expose a `workflow_dispatch` trigger with an input `dry_run` whose default is `true`. When `dry_run` is true, the workflow SHALL enumerate candidates and log them but SHALL NOT issue any DELETE request.

The experience context is the maintainer poking the workflow ad-hoc — they expect to see the candidate list before anything destructive happens, and to opt in to deletion explicitly by flipping the input.

#### Scenario: workflow_dispatch with default input previews only

- **GIVEN** a maintainer triggers the workflow via the *Actions* UI without changing inputs
- **WHEN** the workflow runs
- **THEN** the workflow logs every candidate version id with its `created_at` and (empty) tag list
- **AND** the workflow log contains zero `DELETE` lines
- **AND** no version is removed from GHCR

#### Scenario: workflow_dispatch with dry_run=false deletes

- **GIVEN** a maintainer triggers the workflow with `dry_run: false`
- **WHEN** the workflow runs
- **THEN** every candidate version is deleted (same effect as a scheduled run)

#### Scenario: Scheduled trigger deletes by default

- **GIVEN** the cron schedule fires
- **WHEN** the workflow runs
- **THEN** every candidate version is deleted without requiring any input override

### Requirement: Pruning is idempotent

A pruning run that finds zero candidates SHALL exit 0. A DELETE that returns 404 (version already deleted by a prior race) SHALL be logged and treated as success.

The experience context is the on-call maintainer reading workflow logs — they expect a no-op run on a clean registry to look identical to a successful run, not to fail.

#### Scenario: Clean registry produces a no-op success

- **GIVEN** every untagged version on the package is < 7 days old
- **WHEN** the workflow runs
- **THEN** the workflow logs "0 candidates" and exits 0

#### Scenario: Concurrent delete is not an error

- **GIVEN** a candidate version id was deleted by a prior run between enumeration and DELETE
- **WHEN** this run issues DELETE for that id
- **THEN** the 404 response is logged and the workflow continues with the next candidate
- **AND** the workflow exits 0 if no other failures occurred

### Requirement: Pruning workflow runs with minimum privilege

The workflow SHALL declare `permissions: { packages: write, contents: read }` and SHALL NOT request any other permission. It SHALL use the workflow `GITHUB_TOKEN` — no personal access token or external secret.

The experience context is the security reviewer auditing the unattended scheduled job — they need to confirm the workflow cannot reach beyond the package and cannot publish secrets.

#### Scenario: Workflow does not run on push or pull_request

- **GIVEN** a push to main or a pull_request open
- **WHEN** GitHub fires workflow events
- **THEN** this workflow does not appear in the run list for those events

#### Scenario: Workflow uses GITHUB_TOKEN with packages:write

- **GIVEN** the workflow file
- **WHEN** a maintainer reads its `permissions:` block
- **THEN** only `packages: write` and `contents: read` are requested
- **AND** no `secrets.*` other than `GITHUB_TOKEN` is referenced
