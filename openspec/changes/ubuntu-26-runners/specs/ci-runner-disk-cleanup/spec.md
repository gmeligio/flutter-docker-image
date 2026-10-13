## MODIFIED Requirements

### Requirement: Single action reference works on both supported runner OSes

`.github/actions/clean-runner-disk` SHALL be a single composite action invocable from any workflow job running on either `ubuntu-26.04` or `windows-2025` with the same `uses: ./.github/actions/clean-runner-disk` reference. The action SHALL dispatch its cleanup logic by `runner.os` internally; workflow YAML SHALL NOT branch on OS to choose between action paths.

The experience context is the CI engineer reviewing a workflow that needs runner disk space — they reference one action, see one diff in PRs that touch cleanup behavior, and do not need to remember a separate path for the Windows job.

#### Scenario: Linux job invokes the action

- **GIVEN** a workflow job with `runs-on: ubuntu-26.04` that calls `uses: ./.github/actions/clean-runner-disk`
- **WHEN** the action runs
- **THEN** only the Linux cleanup steps execute (Windows-gated steps are skipped)
- **AND** the job continues normally after cleanup

#### Scenario: Windows job invokes the action

- **GIVEN** a workflow job with `runs-on: windows-2025` that calls `uses: ./.github/actions/clean-runner-disk`
- **WHEN** the action runs
- **THEN** only the Windows cleanup steps execute (Linux-gated steps are skipped)
- **AND** the job continues normally after cleanup

#### Scenario: Unsupported runner OS is rejected loudly

- **GIVEN** a future workflow job with `runs-on: macos-14` that calls `uses: ./.github/actions/clean-runner-disk`
- **WHEN** the action runs
- **THEN** the action fails the job with a message naming the unsupported `runner.os`
- **AND** the job does not silently no-op (which would hide the misconfiguration until a downstream OOM)

### Requirement: Linux cleanup completes within a 2-minute wall-clock budget

The Linux cleanup path SHALL complete in ≤ 2 minutes wall-clock at the 95th percentile across the rolling 30-day window of `ci.yml` and `build.yml` runs. The implementation SHALL favor direct `rm -rf` of large directories over `apt-get remove`, which is slow due to dpkg-lock contention and maintainer-script execution per package set. `apt-get autoremove` and `apt-get clean` MAY be retained as a trailing pair to handle dangling dependencies and clear `/var/cache/apt`.

The contract this requirement defends is "freed bytes" (measured by the existing post-clean assertion), NOT "set of removed paths". An implementation that frees ≥ 20 GB on `/` via any tactic SHALL satisfy this requirement, even if it removes fewer packages than a prior implementation.

The experience context is the maintainer measuring CI wall-clock — the previous 3-minute budget assumed `apt-get` was necessary; profiling showed it was the dominant cost without a corresponding safety benefit, since the post-clean assertion is the real safety net.

#### Scenario: Linux cleanup runs within budget on a standard runner

- **GIVEN** an `ubuntu-26.04` runner with the standard pre-installed toolchains
- **WHEN** the cleanup action runs
- **THEN** the action completes in ≤ 2 minutes at the median across 5 runs
- **AND** the post-clean assertion (`≥ 20 GB free on /`) passes

#### Scenario: Cleanup tactic may differ as long as freed-bytes contract holds

- **GIVEN** an implementation that uses only `rm -rf` (no `apt-get remove`)
- **WHEN** the cleanup action runs
- **THEN** the post-clean assertion passes (`≥ 20 GB free on /`)
- **AND** the requirement is satisfied even though apt's package metadata still references files that no longer exist on disk
- **AND** no downstream step in `build.yml` or `ci.yml` queries apt-database consistency for those packages

#### Scenario: Cleanup tactic regression is detected by the assertion, not by path inventory

- **GIVEN** a future edit removes an `rm -rf` line, leaving < 20 GB free
- **WHEN** the cleanup action runs
- **THEN** the post-clean assertion fails the step with the actual free-space number
- **AND** the regression is caught at the cleanup step rather than at a downstream `docker build` "no space left on device"

