# ci-workflow-readability Specification

## Purpose

Define the naming and structure conventions that make `.github/workflows/` legible at a glance — kebab-case filenames with Title Case `name:` labels, kebab-case job ids with Title Case job names, and a single release-prep workflow whose changelog→tag path is one visible job graph. The experience context is the maintainer scanning `ls .github/workflows/`, the Actions sidebar, the PR checks list, and the job graph: every convention here turns a derived-from-filename default or a hidden cross-workflow chain into a readable, self-evident label, and a contributor copying a workflow as a template inherits the convention automatically.

## Requirements

### Requirement: Every workflow file uses a kebab-case filename and a Title Case `name:`

Every file under `.github/workflows/` SHALL be named in kebab-case (hyphens, no underscores, no leading-underscore convention) and SHALL declare a top-level `name:` in Title Case for the Actions sidebar.

The experience context is the maintainer scanning `ls .github/workflows/` and the Actions sidebar: the file listing is uniform, and each workflow shows a readable label instead of a derived-from-filename default. A contributor copying a workflow as a template inherits the convention automatically.

This is convention-by-example, not an official GitHub standard — GitHub's own `actions/starter-workflows` repo and official actions use kebab-case, and no official ruling exists. The repo adopts kebab-case as its house rule.

#### Scenario: A workflow file is renamed in this change

- **GIVEN** `update_docs.yml`, `cleanup_pr_image.yml`, and `update_version.yml` are renamed to their kebab-case equivalents
- **WHEN** the rename lands
- **THEN** no file under `.github/workflows/` contains `_`
- **AND** each renamed file declares a top-level `name:`

#### Scenario: A new workflow is added in a future PR

- **GIVEN** a contributor adds a new workflow file
- **WHEN** they choose a filename
- **THEN** the filename uses kebab-case and the file declares a Title Case `name:`
- **AND** if it uses underscores, the PR is corrected at review

### Requirement: Every job uses a kebab-case id (YAML key) and a Title Case `name:`

Every job under `jobs:` in every workflow SHALL use a kebab-case `<job-id>` YAML key and SHALL declare a `name:` written as a Title Case verb phrase. Every `needs:` reference, every `${{ needs.<id>.outputs.* }}` expression, and every `github.job` read SHALL be updated to match the kebab-case ids.

The experience context is the maintainer reading the PR checks list and the Actions job graph: each job shows a human-readable label (`Build and push image`, `Scan image`) instead of a bare snake_case id, and the `needs:` graph reads consistently with kebab-case keys.

#### Scenario: A job id is renamed to kebab-case

- **GIVEN** a job previously keyed `build_image` is renamed to `build-image`
- **WHEN** the rename lands
- **THEN** every `needs: [..., build-image]` and `needs.build-image.outputs.*` reference is updated in the same commit
- **AND** no workflow contains a dangling `needs.<old_id>` or `github.job`-derived reference to the old id

#### Scenario: The Actions UI shows readable job labels

- **GIVEN** a workflow run with jobs that declare `name:` keys
- **WHEN** the maintainer views the run or the PR checks list
- **THEN** each job displays its Title Case `name:` (e.g. `Scan image`) rather than the bare job id

#### Scenario: A required status check is pinned by job name

- **GIVEN** branch protection pins a required status check by `<workflow> / <job-name>`
- **WHEN** the job id or `name:` changes in this change
- **THEN** the pinned check name is updated in repo settings before merge
- **AND** the post-merge run is not blocked on a stale pin

### Requirement: The release-prep step is one workflow that tags the merged version

The path from "version manifest changed" to "tag exists" SHALL be a single workflow `.github/workflows/prepare-release.yml` containing one job, `create-tag`. The intermediate `changelog.md`-push trigger that previously chained `changelog.yml` → `tag.yml` SHALL NOT exist, and neither SHALL a changelog-committing job inside `prepare-release.yml`: the changelog is generated upstream in the version-bump pull request, and `release.yml` regenerates its own notes from history, so nothing in release prep writes a commit to `main`. Tag creation SHALL use the GitHub App installation token rather than `GITHUB_TOKEN`, because GitHub suppresses workflow triggers for `GITHUB_TOKEN` pushes and the tag must trigger `release.yml`.

The experience context is the maintainer debugging release prep: one run, one log, one job instead of two separate runs whose connection is visible only by reading both YAML files — and a CI engineer who sees the image published for a new Flutter version because the tag actually fired the release.

#### Scenario: A version bump merges to `main`

- **GIVEN** a pull request that bumps `config/version.json` merges to `main`
- **WHEN** `prepare-release.yml` runs
- **THEN** `create-tag` pushes the new version tag
- **AND** the new tag triggers `release.yml`
- **AND** no commit is pushed to `main` by release prep

#### Scenario: The version is already tagged

- **GIVEN** a run of `prepare-release.yml` for a version whose tag already exists
- **WHEN** `create-tag` evaluates the manifest
- **THEN** it creates no tag and the run succeeds
- **AND** no duplicate release is produced
