# ci-runner-disk-cleanup Specification

## Purpose

Define what `.github/actions/clean-runner-disk` SHALL achieve on the GitHub-hosted runners used by this repo (`ubuntu-24.04` and `windows-2025`) — minimum disk freed, maximum wall-clock spent, observability of the result, and the contract that both runner OSes are invoked via the same action reference from any workflow that needs cleanup.
## Requirements
### Requirement: Single action reference works on both supported runner OSes

`.github/actions/clean-runner-disk` SHALL be a single composite action invocable from any workflow job running on either `ubuntu-24.04` or `windows-2025` with the same `uses: ./.github/actions/clean-runner-disk` reference. The action SHALL dispatch its cleanup logic by `runner.os` internally; workflow YAML SHALL NOT branch on OS to choose between action paths.

The experience context is the CI engineer reviewing a workflow that needs runner disk space — they reference one action, see one diff in PRs that touch cleanup behavior, and do not need to remember a separate path for the Windows job.

#### Scenario: Linux job invokes the action

- **GIVEN** a workflow job with `runs-on: ubuntu-24.04` that calls `uses: ./.github/actions/clean-runner-disk`
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

### Requirement: Windows cleanup completes within a 4-minute wall-clock budget

The Windows cleanup path SHALL complete in ≤ 6 minutes wall-clock at the 95th percentile across the rolling 30-day window of `windows.yml` runs (≥ 40 % faster than the pre-change ~10.7-minute baseline). Implementation SHALL use the fastest native deletion strategy available on `windows-2025` measured against the actual runner image — not chosen from public benchmarks of unrelated workloads. The current shipped strategy is PowerShell 7 `ForEach-Object -Parallel` over `Remove-Item -Recurse -Force` with `ThrottleLimit 8`; substitution is permitted whenever a measured run on `windows-2025` demonstrates a lower wall-clock at equivalent free-space outcome.

The experience context is the maintainer watching the PR check page — the Windows job dropping by ~6 minutes is the user-visible payoff of this capability, and a regression back toward 10 minutes is a real complaint.

#### Scenario: Typical Windows runner image, every target removed cleanly

- **GIVEN** a `windows-2025` runner with the standard set of pre-installed toolchains (Android SDK, hostedtoolcache, dotnet, msys64, Strawberry Perl, Miniconda, Chrome, Firefox, vcpkg, etc.)
- **WHEN** the cleanup action runs and every target directory is removed on the first attempt
- **THEN** the action completes in ≤ 6 minutes
- **AND** every target directory is gone from disk

#### Scenario: A target directory resists removal

- **GIVEN** one target directory contains a long path (>260 chars), a locked file, or an ACL-protected entry that `Remove-Item` cannot fully remove
- **WHEN** the cleanup action runs
- **THEN** the parallel runspace for that path completes (`-ErrorAction Continue`) without aborting the other parallel removals
- **AND** the action emits `::warning::<path> still present after removal` so the surviving directory is named in the log
- **AND** the post-clean free-space assertion (see "Action asserts minimum post-clean free space") catches any case where enough survived to threaten the downstream `docker build`

### Requirement: Action asserts minimum post-clean free space and fails loudly on regression

After cleanup, the action SHALL check free space on the build drive (`/` on Linux, `C:` on Windows) and SHALL fail the step with a message naming the actual free space and the threshold when free space is below 20 GB on Linux or 40 GB on Windows.

The experience context is the maintainer whose runner image GitHub silently updated overnight to add a new 15 GB tool — without the assertion they would wait 25 minutes for `docker build` to fail with "no space left on device"; with the assertion the job fails at the cleanup step with a typed message that names what is full.

#### Scenario: Cleanup achieves enough free space

- **GIVEN** the runner has ≥ 20 GB free on `/` after Linux cleanup, or ≥ 40 GB free on `C:` after Windows cleanup
- **WHEN** the post-clean assertion runs
- **THEN** the assertion passes
- **AND** the job continues to the Docker build

#### Scenario: Cleanup did not free enough space

- **GIVEN** an underlying change (script bug, runner image update introducing a new large toolchain not in the removal list) leaves < 20 GB free on Linux or < 40 GB free on Windows
- **WHEN** the post-clean assertion runs
- **THEN** the assertion fails the step with `core.setFailed`
- **AND** the failure message names the actual free space, the threshold, and the top 5 remaining directories by size
- **AND** the Docker build does not run

### Requirement: Action emits a one-line job summary

The action SHALL append a single line to `$GITHUB_STEP_SUMMARY` (or the PowerShell-equivalent file path on Windows) in the form `clean-runner-disk: freed <X> GB in <Y>m <Z>s on <os>`. The line SHALL be emitted once per invocation and SHALL NOT require expanding the step logs to read.

The experience context is the maintainer scanning the PR check page for slow steps — the summary line surfaces the cleanup cost without log-scraping, which is how the bottleneck was discovered in the first place.

#### Scenario: Summary appears on the run page after success

- **GIVEN** any successful invocation of the action on any supported runner
- **WHEN** the run completes
- **THEN** the run summary on the PR check page contains a single line matching `^clean-runner-disk: freed [0-9.]+ GB in [0-9]+m [0-9]+s on (Linux|Windows)$`

#### Scenario: Summary appears even when the assertion fails

- **GIVEN** an invocation where the post-clean assertion fails (free space below threshold)
- **WHEN** the run completes (with the step marked failed)
- **THEN** the summary still contains the line so a maintainer can compare the freed-bytes number against historical values

### Requirement: Linux cleanup completes within a 2-minute wall-clock budget

The Linux cleanup path SHALL complete in ≤ 2 minutes wall-clock at the 95th percentile across the rolling 30-day window of `ci.yml` and `build.yml` runs. The implementation SHALL favor direct `rm -rf` of large directories over `apt-get remove`, which is slow due to dpkg-lock contention and maintainer-script execution per package set. `apt-get autoremove` and `apt-get clean` MAY be retained as a trailing pair to handle dangling dependencies and clear `/var/cache/apt`.

The contract this requirement defends is "freed bytes" (measured by the existing post-clean assertion), NOT "set of removed paths". An implementation that frees ≥ 20 GB on `/` via any tactic SHALL satisfy this requirement, even if it removes fewer packages than a prior implementation.

The experience context is the maintainer measuring CI wall-clock — the previous 3-minute budget assumed `apt-get` was necessary; profiling showed it was the dominant cost without a corresponding safety benefit, since the post-clean assertion is the real safety net.

#### Scenario: Linux cleanup runs within budget on a standard runner

- **GIVEN** an `ubuntu-24.04` runner with the standard pre-installed toolchains
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

