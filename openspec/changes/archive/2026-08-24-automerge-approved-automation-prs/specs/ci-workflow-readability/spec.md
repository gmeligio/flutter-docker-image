## MODIFIED Requirements

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
