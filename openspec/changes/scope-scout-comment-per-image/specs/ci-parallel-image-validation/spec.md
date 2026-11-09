## MODIFIED Requirements

### Requirement: Scan job preserves the existing fork-PR gate

`scan_image` SHALL preserve the gate that today restricts `docker/scout-action` to non-fork PRs (Scout requires the Docker Hub org secret, and the per-image PR comment requires a write token, neither available to fork PRs). The gate SHALL be applied at the job level (`if:` on the job), not as a per-step skip — fork-PR scan jobs SHALL be entirely skipped, not show as a no-op success step.

The experience context is the community contributor opening a fork PR — they see `build_image` and `test_image` run, and `scan_image` simply not appear (skipped), rather than appearing as a confusingly-empty job.

#### Scenario: Fork PR skips scan_image entirely

- **GIVEN** a `pull_request` event with `github.event.pull_request.head.repo.full_name != github.repository`
- **WHEN** the workflow runs
- **THEN** `scan_image` does not appear in the run's job list (job-level `if:` evaluates to false)
- **AND** the run still completes successfully when `build_image` and `test_image` succeed
