## ADDED Requirements

### Requirement: All image builds go through the `build-image.yml` reusable workflow

Every workflow under `.github/workflows/` that builds a Docker image SHALL invoke `.github/workflows/build-image.yml` via `uses: ./.github/workflows/build-image.yml`. No workflow SHALL inline `docker/metadata-action`, `docker/build-push-action`, or `container-structure-test-action` outside the reusable workflow.

The experience context is the maintainer changing image-build behavior (e.g. switching cache backends, adding a `--sbom` flag, swapping the structure-test image): the change touches one file and applies to PR builds, main builds, Windows builds, and release builds at once. Drift between callers becomes impossible by construction.

#### Scenario: A new workflow needs to build an image

- **GIVEN** a contributor adds a workflow that needs to build an image (e.g. a nightly build)
- **WHEN** the workflow is reviewed
- **THEN** it calls `uses: ./.github/workflows/build-image.yml` with the appropriate inputs
- **AND** it does NOT inline `docker/build-push-action` or any of its peer steps

#### Scenario: An image-build change needs to apply everywhere

- **GIVEN** the maintainer wants to add `provenance: mode=max` to every image build
- **WHEN** they make the change
- **THEN** the diff touches only `.github/workflows/build-image.yml`
- **AND** every caller workflow inherits the change

### Requirement: The reusable workflow accepts a stable, documented input shape

`build-image.yml` SHALL declare its `inputs:` and `secrets:` schema in the file header with a comment for each field describing valid values and defaults. Inputs SHALL include at minimum: `runner-os`, `dockerfile`, `image-name`, `push-to-registries`, `cache-mode`, `tag-prefix`. Secrets SHALL include `dockerhub-username`, `dockerhub-token`, `quay-username`, `quay-token`, all `required: false`.

The experience context is a contributor adding a new caller — they read the file header and know exactly what to pass without spelunking through the workflow body.

#### Scenario: A caller passes an unknown input

- **GIVEN** a caller passes an input not declared in `build-image.yml`'s schema
- **WHEN** the workflow runs
- **THEN** GitHub Actions rejects the call with a clear error

#### Scenario: A caller omits an optional secret

- **GIVEN** a fork PR caller does not pass `dockerhub-token`
- **WHEN** `build-image.yml` runs
- **THEN** the Docker Hub login step is skipped (the inner `docker-registry-login` composite respects the omitted secret)
- **AND** the image build still completes for GHCR-only consumers

### Requirement: The reusable workflow emits image identifiers as outputs

`build-image.yml` SHALL emit at least `image-digest`, `image-tag`, and `metadata-json` as outputs at the workflow_call level. Callers SHALL be able to reference these via `needs.<caller-job>.outputs.<name>`.

The experience context is the caller workflow that needs to scan, sign, or release the built image — it consumes a digest from the reusable workflow's output rather than re-querying the registry.

#### Scenario: `release.yml` needs the digest to attach a Docker Scout report

- **GIVEN** `release.yml` calls `build-image.yml` and then needs to run `docker/scout-action` against the built image
- **WHEN** the scout job runs
- **THEN** it reads the digest from the reusable workflow's `image-digest` output
- **AND** it does not query the registry for the digest separately

## ADDED Requirements

### Requirement: The release-prep chain is one workflow, not three

The path from "version manifest changed" to "tag exists" SHALL be a single workflow `.github/workflows/prepare-release.yml` with two sequential jobs (`update-changelog` → `create-tag` via `needs:`). The intermediate file-push trigger that previously chained `changelog.yml` → `tag.yml` SHALL NOT exist.

The experience context is the maintainer who needs to understand or debug the release prep — one workflow run, one log, one job graph instead of two separate runs whose connection is only visible by reading both YAML files.

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

### Requirement: Workflow file names use kebab-case

Every file under `.github/workflows/` SHALL be named with hyphens, not underscores. No file SHALL use a leading-underscore convention to mark reusable workflows (`workflow_call` is the marker, not the filename).

The experience context is the maintainer scanning `ls .github/workflows/` — the listing is uniform and a contributor copying a workflow as a template inherits the convention automatically.

#### Scenario: A workflow is renamed in this change

- **GIVEN** `update_version.yml`, `update_docs.yml`, `cleanup_pr_image.yml` are renamed to their kebab-case equivalents
- **WHEN** the rename lands
- **THEN** no file under `.github/workflows/` contains `_`
- **AND** the rename is a single commit so `git log --follow` traces history cleanly

#### Scenario: A new workflow is added in a future PR

- **GIVEN** a contributor adds a new workflow
- **WHEN** they choose a filename
- **THEN** the filename uses kebab-case (no underscores, no leading underscore)
- **AND** if they use underscores, the PR is blocked at review

## MODIFIED Requirements

### Requirement: Image build cache backend is selected per call site

The Docker layer cache backend (`type=gha` for PRs, `type=registry,ref=...` for main/releases) SHALL be selected by passing the `cache-mode` input to `build-image.yml`. Callers SHALL NOT inline cache-from/cache-to declarations; the reusable workflow centralizes the cache configuration so that "swap GHA cache for a different backend" is a one-file change.

The experience context is the maintainer evaluating a new cache backend — they edit one file, all four image-building callers pick it up, and they compare hit-rate metrics across the matrix in a single run.

#### Scenario: A PR build uses GHA cache

- **GIVEN** `build.yml` calls `build-image.yml` with `cache-mode: 'gha'`
- **WHEN** the build runs
- **THEN** the reusable workflow configures `cache-from: type=gha` and `cache-to: type=gha,mode=max`

#### Scenario: A main-branch build uses registry cache

- **GIVEN** `ci.yml` calls `build-image.yml` with `cache-mode: 'registry'`
- **WHEN** the build runs
- **THEN** the reusable workflow configures `cache-from: type=registry,ref=...` and `cache-to: type=registry,ref=...,mode=max`
