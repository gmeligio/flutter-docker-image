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

### Requirement: Action asserts minimum post-clean free space and fails loudly on regression

After cleanup, or after the Linux path decides cleanup is not needed, the action SHALL check free space on the build drive (`/` on Linux, `C:` on Windows) and SHALL fail the step with a message naming the actual free space and the threshold when free space is below 30 GB on Linux or 40 GB on Windows.

The Linux minimum is sized from measured `ubuntu-26.04` builds: the largest measured build (`flutter-android` loaded into the local Docker daemon in `ci.yml`) used ~12 GB of `/`, and the fork path, which also writes a gzipped image tarball, is estimated at ~23 GB. 30 GB covers that with margin.

The experience context is the maintainer whose runner image GitHub silently updated overnight to add a new 15 GB tool — without the assertion they would wait 25 minutes for `docker build` to fail with "no space left on device"; with the assertion the job fails at the cleanup step with a typed message that names what is full.

#### Scenario: Cleanup achieves enough free space

- **GIVEN** the runner has ≥ 30 GB free on `/` after the Linux path, or ≥ 40 GB free on `C:` after Windows cleanup
- **WHEN** the post-clean assertion runs
- **THEN** the assertion passes
- **AND** the job continues to the Docker build

#### Scenario: Cleanup did not free enough space

- **GIVEN** an underlying change (script bug, runner image update introducing a new large toolchain not in the removal list) leaves < 30 GB free on Linux or < 40 GB free on Windows
- **WHEN** the post-clean assertion runs
- **THEN** the assertion fails the step
- **AND** the failure message names the actual free space, the threshold, and the top 5 remaining directories by size
- **AND** the Docker build does not run

### Requirement: Linux cleanup completes within a 2-minute wall-clock budget

When the Linux cleanup runs, it SHALL complete in ≤ 2 minutes wall-clock at the 95th percentile across the rolling 30-day window of `ci.yml` and `build.yml` runs that performed cleanup. Invocations that skip cleanup (see "Linux cleanup runs only when free space is below the minimum") SHALL NOT count toward this budget. The implementation SHALL favor direct `rm -rf` of large directories over `apt-get remove`, which is slow due to dpkg-lock contention and maintainer-script execution per package set. `apt-get autoremove` and `apt-get clean` MAY be retained as a trailing pair to handle dangling dependencies and clear `/var/cache/apt`.

The contract this requirement defends is "freed bytes" (measured by the existing post-clean assertion), NOT "set of removed paths". An implementation that leaves ≥ 30 GB free on `/` via any tactic SHALL satisfy this requirement, even if it removes fewer packages than a prior implementation.

The experience context is the maintainer measuring CI wall-clock — the previous 3-minute budget assumed `apt-get` was necessary; profiling showed it was the dominant cost without a corresponding safety benefit, since the post-clean assertion is the real safety net.

#### Scenario: Linux cleanup runs within budget on a standard runner

- **GIVEN** an `ubuntu-26.04` runner with less than 30 GB free on `/` and the standard pre-installed toolchains
- **WHEN** the cleanup action runs
- **THEN** the action completes in ≤ 2 minutes at the median across 5 runs
- **AND** the post-clean assertion (`≥ 30 GB free on /`) passes

#### Scenario: Cleanup tactic may differ as long as freed-bytes contract holds

- **GIVEN** an implementation that uses only `rm -rf` (no `apt-get remove`)
- **WHEN** the cleanup action runs
- **THEN** the post-clean assertion passes (`≥ 30 GB free on /`)
- **AND** the requirement is satisfied even though apt's package metadata still references files that no longer exist on disk
- **AND** no downstream step in `build.yml` or `ci.yml` queries apt-database consistency for those packages

#### Scenario: Cleanup tactic regression is detected by the assertion, not by path inventory

- **GIVEN** a future edit removes an `rm -rf` line, leaving < 30 GB free
- **WHEN** the cleanup action runs
- **THEN** the post-clean assertion fails the step with the actual free-space number
- **AND** the regression is caught at the cleanup step rather than at a downstream `docker build` "no space left on device"

## ADDED Requirements

### Requirement: Linux cleanup runs only when free space is below the minimum

Before removing anything, the Linux path SHALL read the free space on `/`. When it is at least the Linux minimum (30 GB), the action SHALL skip the package listing, the removals and the post-clean disk-usage report, and SHALL log that cleanup was skipped with the free space it found. The post-clean assertion and the job summary line SHALL still run, with the summary reporting `freed 0.00 GB`.

The experience context is the maintainer watching PR check times. `ubuntu-26.04` runners start with ~90 GB free on a 145 GB disk, three times the minimum, yet the cleanup took 2m37s–4m06s per image build. Skipping it when it cannot change the outcome removes that time from every Linux build, while keeping the cleanup as a safety net if runner images shrink the free space.

#### Scenario: Runner already has enough free space

- **GIVEN** an `ubuntu-26.04` runner with ≥ 30 GB free on `/`
- **WHEN** the cleanup action runs
- **THEN** no toolchain directory is removed and `apt-get` is not called
- **AND** the log states that cleanup was skipped and how much was free
- **AND** the post-clean assertion passes and the summary line reports `freed 0.00 GB`

#### Scenario: Runner is below the minimum

- **GIVEN** a runner with < 30 GB free on `/`
- **WHEN** the cleanup action runs
- **THEN** the full Linux cleanup runs as before
- **AND** the post-clean assertion checks for ≥ 30 GB free on `/`
