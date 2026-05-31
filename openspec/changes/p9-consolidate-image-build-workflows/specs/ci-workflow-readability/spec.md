## ADDED Requirements

### Requirement: Every workflow file uses a kebab-case filename and a Title Case `name:`

Every file under `.github/workflows/` SHALL be named in kebab-case (hyphens, no underscores, no leading-underscore convention) and SHALL declare a top-level `name:` in Title Case for the Actions sidebar.

The experience context is the maintainer scanning `ls .github/workflows/` and the Actions sidebar: the file listing is uniform, and each workflow shows a readable label instead of a derived-from-filename default. A contributor copying a workflow as a template inherits the convention automatically.

This is convention-by-example, not an official GitHub standard — GitHub's own `actions/starter-workflows` repo and official actions use kebab-case, and no official ruling exists. The repo adopts kebab-case as its house rule.

#### Scenario: A workflow file is renamed in this change

- **GIVEN** `update_docs.yml` and `cleanup_pr_image.yml` are renamed to their kebab-case equivalents
- **WHEN** the rename lands
- **THEN** no file under `.github/workflows/` contains `_` except the deferred `update_version.yml` (renamed in a post-p12 follow-up)
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

### Requirement: The changelog→tag release-prep step is one workflow with a visible job graph

The path from "version manifest changed" to "tag exists" SHALL be a single workflow `.github/workflows/prepare-release.yml` with two sequential jobs (`update-changelog` → `create-tag` via `needs:`). The intermediate `changelog.md`-push trigger that previously chained `changelog.yml` → `tag.yml` SHALL NOT exist. The App-token identity used to push SHALL be unchanged so the tag push still triggers `release.yml`.

The experience context is the maintainer debugging release prep: one run, one log, one job graph instead of two separate runs whose connection is visible only by reading both YAML files.

#### Scenario: A version bump merges to `main`

- **GIVEN** a PR that bumps `config/version.json` merges to `main`
- **WHEN** `prepare-release.yml` runs
- **THEN** `update-changelog` runs first and commits `changelog.md`
- **AND** `create-tag` runs next (via `needs:`) and pushes the new tag
- **AND** the new tag triggers `release.yml` exactly as before this change

#### Scenario: `update-changelog` fails

- **GIVEN** the changelog generation fails (e.g. git-cliff error)
- **WHEN** the job fails
- **THEN** `create-tag` does not run (skipped by `needs:` semantics)
- **AND** no orphan tag is created without a matching changelog commit
