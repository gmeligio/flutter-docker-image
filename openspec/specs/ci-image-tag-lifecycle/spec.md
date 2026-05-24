# ci-image-tag-lifecycle Specification

## Purpose

Delete temporary handoff tags (`pr-<N>` and `branch-<branch>`) on `ghcr.io/<owner>/flutter-android` when the PR closes or the branch is deleted, so the registry does not accumulate dead-weight tags while leaving release tags untouched.

## Requirements

### Requirement: PR-close deletes the corresponding handoff tag

When a `pull_request` closes (merged or not), a workflow SHALL delete the GHCR tag `ghcr.io/<owner>/flutter-android:pr-<N>` corresponding to that PR number, if it exists.

The experience context is the maintainer auditing GHCR storage — they expect to see one tag per open PR, not per ever-opened PR.

#### Scenario: Closing a merged PR removes the handoff tag

- **GIVEN** PR #42 was opened on a same-repo branch, ran `build.yml`, and produced `ghcr.io/<owner>/flutter-android:pr-42`
- **WHEN** PR #42 is merged
- **THEN** the cleanup workflow runs and deletes `pr-42` from GHCR within 60 seconds
- **AND** the GHCR tag list no longer contains `pr-42`

#### Scenario: Closing an unmerged PR removes the handoff tag

- **GIVEN** PR #42 produced `pr-42` and is closed without merging
- **WHEN** the cleanup workflow runs
- **THEN** `pr-42` is deleted from GHCR

#### Scenario: Cleanup is idempotent when the tag does not exist

- **GIVEN** PR #42 is from a fork (p2 used the artifact path; no GHCR tag was created)
- **WHEN** PR #42 closes and the cleanup workflow runs
- **THEN** the workflow logs "tag not found, nothing to delete"
- **AND** the workflow exits 0 (does not fail)

### Requirement: Branch deletion deletes the corresponding branch handoff tag

When a branch is deleted (`delete` event with `ref_type == 'branch'`), the cleanup workflow SHALL delete the GHCR tag `branch-<branch-name>` (with `/` → `-`) if it exists.

The experience context is the maintainer running `workflow_dispatch` on a feature branch, then deleting the branch — they expect the `branch-<name>` tag to disappear automatically.

#### Scenario: Branch deletion removes the branch handoff tag

- **GIVEN** branch `feature/new-cache` was tested via `workflow_dispatch`, producing `ghcr.io/<owner>/flutter-android:branch-feature-new-cache`
- **WHEN** the branch is deleted
- **THEN** the cleanup workflow runs, computes `branch-feature-new-cache` from the deleted ref, and deletes the tag

### Requirement: Cleanup never targets a non-handoff tag

The cleanup workflow SHALL refuse to issue a delete request for any tag that does not match the documented temporary-tag regex (`^pr-[0-9]+$` or `^branch-[A-Za-z0-9._-]+$`). Tags such as the Flutter version release tags (e.g. `3.41.9`) or the `buildcache` tag SHALL be unreachable from this workflow's code path.

The experience context is the maintainer auditing the cleanup workflow before merging — they need confidence that a future edit cannot accidentally delete a release tag.

#### Scenario: Release tag is never considered for deletion

- **GIVEN** a release tag `3.41.9` and a handoff tag `pr-42` both exist
- **WHEN** PR #42 closes
- **THEN** only `pr-42` is deleted
- **AND** the workflow does not enumerate other tags
- **AND** `3.41.9` remains untouched

#### Scenario: Misshapen target tag fails closed

- **GIVEN** a code path that somehow computes a target tag of `latest` or `3.41.9` (e.g. a future bug)
- **WHEN** the regex assertion runs
- **THEN** the workflow fails the step with a message naming the offending tag
- **AND** no delete request is sent to GHCR

### Requirement: Cleanup workflow runs with minimum privilege

The workflow SHALL declare `permissions: { packages: write, contents: read }` and SHALL NOT request any other permission. Cleanup runs only on `pull_request: closed` and `delete` events — it SHALL NOT run on `push`, `pull_request: opened`, or `pull_request: synchronize`.

The experience context is the security reviewer ensuring an unauthenticated event cannot trigger the destructive workflow.

#### Scenario: Workflow does not run on PR open or synchronize

- **GIVEN** a PR is opened or pushed to
- **WHEN** GitHub fires workflow events
- **THEN** the cleanup workflow does not appear in the run list for those events
