## ADDED Requirements

### Requirement: Build job exposes a handoff for downstream jobs

The CI job that builds the Flutter Docker image SHALL expose two job outputs that downstream jobs in the same workflow run can consume to access the image without rebuilding it:

- `image_ref`: the full registry reference (`ghcr.io/<owner>/flutter-android:<tag>`) when the build pushed to GHCR.
- `image_artifact`: the artifact name (`image-<run_id>`) when the build uploaded a `docker save` tarball instead.

Exactly one output SHALL be non-empty per run. A consumer SHALL be able to decide its pull strategy from the outputs alone, without inspecting `github.event` itself.

The experience context is a maintainer adding a new validation step in a later change — they look at the build job's outputs, see exactly one channel populated, and write a single consumer that branches on which channel.

#### Scenario: Outputs encode the handoff kind unambiguously

- **GIVEN** any successful build run
- **WHEN** the run completes
- **THEN** exactly one of `image_ref` and `image_artifact` is non-empty
- **AND** the non-empty one matches the documented format (`ghcr.io/<owner>/flutter-android:pr-<N>` / `ghcr.io/<owner>/flutter-android:branch-<branch>` or `image-<run_id>`)

### Requirement: Non-fork PRs and workflow_dispatch use the registry handoff

For events that have `packages: write` available on `GITHUB_TOKEN` (`pull_request` from a same-repo head or `workflow_dispatch`), the build SHALL push the image to a deterministic GHCR tag and set `image_ref` to the full registry ref.

The tag format SHALL be:

- `pr-${{ github.event.pull_request.number }}` for `pull_request` events.
- `branch-${{ github.ref_name }}` (with `/` replaced by `-`) for `workflow_dispatch`.

The experience context is the p4 cleanup workflow operator — they need a tag pattern they can match-and-delete on PR close without scanning the registry.

#### Scenario: Non-fork PR pushes the handoff tag

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name == github.repository`
- **WHEN** the build job runs and completes successfully
- **THEN** `ghcr.io/<owner>/flutter-android:pr-<N>` exists in GHCR with the just-built image
- **AND** the job output `image_ref` equals that ref
- **AND** the job output `image_artifact` is empty

#### Scenario: Re-running a PR overwrites the same handoff tag

- **GIVEN** a PR whose build has already produced `pr-<N>` once
- **WHEN** the workflow is re-run for the same PR
- **THEN** the tag `pr-<N>` is overwritten in place (no `pr-<N>-2` or similar accumulation)
- **AND** the prior image bits are eligible for garbage collection by GHCR's regular GC

### Requirement: Fork PRs use an artifact handoff

For `pull_request` events from a fork (where `packages: write` is not available), the build SHALL skip the registry push, save the image with `docker save | gzip`, upload it via `actions/upload-artifact` with retention ≤ 1 day, and set `image_artifact` to the artifact name.

The experience context is a community contributor opening a fork PR — their PR still gets the parallel-validation benefit from later changes (p3), even though the runner cannot push to GHCR.

#### Scenario: Fork PR uploads the image artifact

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name != github.repository`
- **WHEN** the build job runs and completes successfully
- **THEN** an artifact named `image-<run_id>` exists for the run, containing `image.tar.gz`
- **AND** the artifact retention is ≤ 1 day
- **AND** the job output `image_artifact` equals `image-<run_id>`
- **AND** the job output `image_ref` is empty

#### Scenario: Fork PR fallback succeeds even when GHCR is unreachable

- **GIVEN** a fork PR build
- **WHEN** the build completes
- **THEN** no GHCR push is attempted
- **AND** the build does not fail due to missing `packages: write` permission
