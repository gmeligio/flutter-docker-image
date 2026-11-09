# ci-image-handoff Specification

## Purpose

Hand each image built by `build-image` to the `test-image` and `scan-image` legs of the same run without rebuilding it: a GHCR handoff tag for same-repo events, a per-image artifact for fork PRs.

## Requirements

### Requirement: Build job exposes a handoff for downstream jobs

The `build-image` job SHALL expose outputs from which every consumer leg locates its own image without rebuilding it:

- `is_fork`: `true` for a `pull_request` from a fork, otherwise `false`.
- `tag`: the GHCR handoff tag (`pr-<N>` or `branch-<ref>`).
- `flutter_version`: the Flutter version the images were built for.

A consumer SHALL derive its image reference from these outputs plus its own matrix `name`, without inspecting `github.event` itself.

The experience context is a maintainer adding a validation job — they read three outputs and branch once on `is_fork`.

#### Scenario: Outputs encode the handoff kind unambiguously

- **GIVEN** any successful `build-image` run
- **WHEN** the run completes
- **THEN** `is_fork` is `true` or `false`
- **AND** `tag` matches `pr-<N>` or `branch-<ref>`
- **AND** `flutter_version` is non-empty

#### Scenario: Every image declaring a handoff tag produces outputs naming itself

- **GIVEN** `config/images.json` declares more than one image with a pull-request handoff tag
- **WHEN** a consumer leg for image `<name>` runs
- **THEN** it resolves `ghcr.io/<owner>/<name>:<tag>` (non-fork) or `<name>:<flutter_version>` from artifact `image-<run_id>-<name>` (fork)
- **AND** it never resolves a different image's reference

#### Scenario: An image that pushes nothing on a pull request declares no handoff tag

- **GIVEN** an image whose pull-request build does not push to a registry
- **WHEN** the set of handoff-tag producers is derived from the manifest
- **THEN** that image is absent from it
- **AND** no cleanup is attempted for a tag it never created

### Requirement: Non-fork PRs and workflow_dispatch use the registry handoff

For events that have `packages: write` available on `GITHUB_TOKEN` (`pull_request` from a same-repo head or `workflow_dispatch`), each `build-image` leg SHALL push its image to a deterministic GHCR tag and set `is_fork` to `false`.

The tag format SHALL be:

- `pr-${{ github.event.pull_request.number }}` for `pull_request` events.
- `branch-${{ github.ref_name }}` (with `/` replaced by `-`) for `workflow_dispatch`.

The experience context is the cleanup workflow operator — they need a tag pattern they can match-and-delete on PR close without scanning the registry.

#### Scenario: Non-fork PR pushes the handoff tag

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name == github.repository`
- **WHEN** `build-image` runs and completes successfully
- **THEN** `ghcr.io/<owner>/<image>:pr-<N>` exists in GHCR for each image leg, with the just-built image
- **AND** the job output `tag` equals `pr-<N>`
- **AND** the job output `is_fork` equals `false`
- **AND** no image artifact is uploaded

#### Scenario: Re-running a PR overwrites the same handoff tag

- **GIVEN** a PR whose build has already produced `pr-<N>` once
- **WHEN** the workflow is re-run for the same PR
- **THEN** the tag `pr-<N>` is overwritten in place (no `pr-<N>-2` or similar accumulation)
- **AND** the prior image bits are eligible for garbage collection by GHCR's regular GC

### Requirement: Fork PRs use an artifact handoff

For `pull_request` events from a fork (where `packages: write` is not available), each `build-image` leg SHALL skip the registry push, save its image tagged `<image>:<flutter-version>` with `docker save | gzip`, upload it via `actions/upload-artifact` as `image-<run_id>-<image>` with retention ≤ 1 day, and set `is_fork` to `true`.

The experience context is a community contributor opening a fork PR — their image is still tested even though the runner cannot push to GHCR.

#### Scenario: Fork PR uploads the image artifact

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name != github.repository`
- **WHEN** `build-image` runs and completes successfully
- **THEN** an artifact named `image-<run_id>-<image>` exists for each image leg, containing `image.tar.gz`
- **AND** the artifact retention is ≤ 1 day
- **AND** the tarball carries the tag `<image>:<flutter-version>`
- **AND** the job output `is_fork` equals `true`

#### Scenario: Fork PR fallback succeeds even when GHCR is unreachable

- **GIVEN** a fork PR build
- **WHEN** the build completes
- **THEN** no GHCR push is attempted
- **AND** the build does not fail due to missing `packages: write` permission

### Requirement: Consumer jobs never rebuild the image

`test-image` and `scan-image` SHALL obtain the image only through the handoff: pull from GHCR (non-fork) or download the artifact and `docker load` it (fork). Neither SHALL build a Dockerfile.

The experience context is the maintainer auditing CI cost — each image is built once per run, by `build-image`.

#### Scenario: Non-fork consumer pulls without rebuilding

- **GIVEN** a non-fork PR run
- **WHEN** a `Test image (<name>)` or `Scan image (<name>)` check runs
- **THEN** it reads `ghcr.io/<owner>/<name>:<tag>`, where `<tag>` is the `build-image` handoff tag (`pr-<N>` or `branch-<ref>`)
- **AND** its log contains no `docker build` or `buildx build` invocation

#### Scenario: Fork consumer loads the artifact without rebuilding

- **GIVEN** a fork PR run
- **WHEN** a `Test image (<name>)` check runs
- **THEN** it downloads `image-<run_id>-<name>` and runs `docker load`
- **AND** its log contains no `docker build` or `buildx build` invocation

### Requirement: Test and scan validate each image in parallel after build

`test-image` runs one `Test image (<name>)` leg per image in the structure-test set and `scan-image` one `Scan image (<name>)` leg per image in the Scout set, both sets derived from `config/images.json`. Both jobs SHALL depend only on `setup` and `build-image`, never on each other, so both start once the build finishes.

The experience context is the maintainer on the PR checks page — wall-clock after the build is the slower check, not the sum.

#### Scenario: Test and scan start together

- **GIVEN** a non-fork PR run where `build-image` has succeeded and an image is in both sets
- **WHEN** the downstream checks start
- **THEN** `Test image (<name>)` and `Scan image (<name>)` both start without waiting for each other

#### Scenario: An image in only one set gets only that check

- **GIVEN** an image in the structure-test set but not the Scout set
- **WHEN** `build-image` succeeds
- **THEN** `Test image (<name>)` runs and no `Scan image (<name>)` check exists for it

#### Scenario: Build failure skips the consumer jobs

- **GIVEN** any `build-image` leg fails
- **WHEN** the run evaluates downstream jobs
- **THEN** `test-image` and `scan-image` are skipped and report no passing `Test image (<name>)` or `Scan image (<name>)` check
