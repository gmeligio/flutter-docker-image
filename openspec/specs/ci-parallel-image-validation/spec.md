## Requirements

### Requirement: Test and scan run as sibling jobs, not as serial steps

Container-structure-test and Docker Scout SHALL run as two separate GitHub Actions jobs (`test_image` and `scan_image`), each with `needs: build_image`, in the same workflow. They SHALL NOT run as sequential steps inside the same job. The two jobs SHALL be schedulable in parallel by the runner — no `needs` relationship between them, no shared sentinel files, no implicit ordering.

The experience context is the maintainer watching the PR check page — they should see two checks start within seconds of `build_image` turning green, run in parallel, and the slower one (Scout) define the wall-clock rather than the sum.

#### Scenario: Test job runs in parallel with scan job

- **GIVEN** a PR run where `build_image` has just completed successfully
- **WHEN** the runner picks up the downstream jobs
- **THEN** `test_image` and `scan_image` both start within 30 seconds of `build_image` completion
- **AND** their start times are within 30 seconds of each other (no implicit serialization)

#### Scenario: Scout scan runs in parallel with CST

- **GIVEN** a PR run with both consumer jobs running
- **WHEN** the overall wall-clock is measured
- **THEN** total time from `build_image` start to last consumer complete is approximately `build_image_duration + max(test_image_duration, scan_image_duration)` (not the sum)

### Requirement: Consumer jobs do not rebuild the image

`test_image` and `scan_image` SHALL consume the image via the handoff produced by `build_image` (per the `ci-image-handoff` capability). Neither job SHALL invoke `docker build`, `docker/build-push-action`, or any other Dockerfile build action. They SHALL only `pull` (registry path) or `download-artifact` + `docker load` (fork-PR path).

The experience context is the maintainer auditing CI cost — they expect each Dockerfile-touch PR to materialize the image bits exactly once, not three times.

#### Scenario: Consumer pulls registry image without rebuilding

- **GIVEN** a non-fork PR run
- **WHEN** `test_image` or `scan_image` runs
- **THEN** the job log shows a pull (or streaming pull by the action) of `ghcr.io/<owner>/flutter-android:pr-<N>`
- **AND** the job log does not contain `docker build` or `FROM debian:`

#### Scenario: Fork PR consumer loads the artifact without rebuilding

- **GIVEN** a fork PR run
- **WHEN** `test_image` or `scan_image` runs
- **THEN** the job downloads `image-<run_id>`, runs `docker load`, and proceeds
- **AND** the job log does not contain `docker build`

### Requirement: Scan job preserves the existing fork-PR gate

`scan_image` SHALL preserve the gate that today restricts `docker/scout-action` to non-fork PRs (Scout requires the Docker Hub org secret and writes a PR comment, neither available to fork PRs). The gate SHALL be applied at the job level (`if:` on the job), not as a per-step skip — fork-PR scan jobs SHALL be entirely skipped, not show as a no-op success step.

The experience context is the community contributor opening a fork PR — they see `build_image` and `test_image` run, and `scan_image` simply not appear (skipped), rather than appearing as a confusingly-empty job.

#### Scenario: Fork PR skips scan_image entirely

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name != github.repository`
- **WHEN** the workflow runs
- **THEN** `scan_image` does not appear in the run's job list (job-level `if:` evaluates to false)
- **AND** the run still completes successfully when `build_image` and `test_image` succeed

### Requirement: Renamed consumer preserves the existing required-check name

The CST consumer job's key SHALL be `test_image` — the same name as today's monolithic job — so the GitHub Actions check name `test_image` continues to appear and continues to satisfy branch-protection rules that require it. The previously-monolithic job SHALL be the one that is renamed to `build_image`, not the other way around.

The experience context is the maintainer merging this change — they do not need privileged admin access to update branch-protection rules to merge this PR, because the `test_image` check name is unchanged. Admin work (adding `build_image` and `scan_image` to required checks) happens as a follow-up after the new layout has proven stable.

#### Scenario: Renamed consumer satisfies the existing required check

- **GIVEN** branch-protection requires the check name `test_image`
- **WHEN** the workflow runs after this change merges
- **THEN** a check named `test_image` is reported (produced by the CST consumer job)
- **AND** when `build_image` succeeds and the consumer succeeds, the `test_image` check is green
- **AND** the PR can merge without admin intervention

#### Scenario: build_image failure correctly blocks merges

- **GIVEN** `build_image` fails
- **WHEN** `test_image` runs
- **THEN** `test_image` is skipped (its `needs:` failed)
- **AND** the required check `test_image` is not reported
- **AND** branch-protection treats the check as not-satisfied, blocking the merge
