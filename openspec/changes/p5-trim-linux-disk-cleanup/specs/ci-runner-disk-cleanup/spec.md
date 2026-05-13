## MODIFIED Requirements

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
