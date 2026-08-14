# ci-image-tag-lifecycle Specification

## Purpose

Delete temporary handoff tags (`pr-<N>` and `branch-<branch>`) on every image that produces them when the PR closes or the branch is deleted, so the registry does not accumulate dead-weight tags while leaving release tags untouched.

## Requirements

### Requirement: PR-close deletes the corresponding handoff tag

When a `pull_request` closes (merged or not), a workflow SHALL delete the GHCR tag `pr-<N>` corresponding to that PR number, on every image that produces handoff tags, if it exists.

Cleanup SHALL be independent per image: one image's deletion failing SHALL NOT prevent another's from being attempted.

The experience context is the maintainer auditing GHCR storage — they expect to see one tag per open PR, not per ever-opened PR, and not one image cleaned while another accumulates. Scoping cleanup to a single image is what let `flutter-web` accumulate an orphaned handoff tag for every PR it ever built. The named image is not evidence to the contrary: its own three orphans are residue from a separate, bounded failure, not from the scoping this requirement corrects.

#### Scenario: Closing a merged PR removes the handoff tag from every image

- **GIVEN** PR #42 was opened on a same-repo branch, ran `build.yml`, and produced `pr-42` on both `flutter-android` and `flutter-web`
- **WHEN** PR #42 is merged
- **THEN** the cleanup workflow deletes `pr-42` from every image that produced it
- **AND** no image retains `pr-42` because cleanup did not name it

#### Scenario: Closing an unmerged PR removes the handoff tag

- **GIVEN** PR #42 produced `pr-42` and is closed without merging
- **WHEN** the cleanup workflow runs
- **THEN** `pr-42` is deleted from every image that produced it

#### Scenario: Cleanup is idempotent when the tag does not exist

- **GIVEN** PR #42 is from a fork (the artifact path was used; no GHCR tag was created)
- **WHEN** PR #42 closes and the cleanup workflow runs
- **THEN** each leg logs "tag not found, nothing to delete"
- **AND** the workflow exits 0 (does not fail)

#### Scenario: One image's cleanup failure does not skip another's

- **GIVEN** cleanup runs for several images and one image's deletion fails
- **WHEN** the workflow completes
- **THEN** the remaining images' handoff tags have still been deleted
- **AND** only the failing leg is reported red

### Requirement: Branch deletion deletes the corresponding branch handoff tag

When a branch is deleted (`delete` event with `ref_type == 'branch'`), the cleanup workflow SHALL delete the GHCR tag `branch-<branch-name>` (with `/` → `-`) if it exists, on every image that produces handoff tags.

The experience context is the maintainer running `workflow_dispatch` on a feature branch, then deleting the branch — they expect the `branch-<name>` tag to disappear automatically, from every image that built it, not only from the one the workflow happens to name. `build.yml` pushes these for both images on any non-`pull_request` run (`:118-125`), so the single-image gap applies here exactly as it does to `pr-<N>`, even though no such tag happens to exist on GHCR today.

#### Scenario: Branch deletion removes the branch handoff tag from every image

- **GIVEN** branch `feature/new-cache` was tested via `workflow_dispatch`, producing `branch-feature-new-cache` on every image that produces handoff tags
- **WHEN** the branch is deleted
- **THEN** the cleanup workflow computes `branch-feature-new-cache` from the deleted ref and deletes it from each image

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
