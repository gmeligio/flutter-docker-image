## Context

CI in this repo runs on GitHub-hosted runners (`ubuntu-24.04` for `build.yml` / `ci.yml`, `windows-2025` for `windows.yml`). Both jobs build a Flutter Docker image — the Linux runner has ~14 GB of disk that fills up quickly when buildx caches layers, and the Windows runner has more headroom but still benefits from removing 10–15 GB of pre-installed tooling because Windows base images and Visual Studio BuildTools are bulky. To make room, each job runs a custom composite action before the build:

- `.github/actions/clean-runner-disk/` — Linux, uses `apt-get remove` + `rm -rf` (Bash). Median ~3 min.
- `.github/actions/clean-runner-disk-windows/` — Windows, uses PowerShell `Remove-Item -Recurse -Force` over ~20 directories (`C:\Android`, `C:\hostedtoolcache`, `C:\Program Files\dotnet`, `C:\msys64`, `C:\Strawberry`, `C:\Miniconda`, etc.). Median ~10 min, and dominated by NTFS small-file deletion.

The pair were authored at different times for different jobs and have drifted: the Linux variant removes Rust/Haskell/Julia/Swift toolchains the Windows variant doesn't bother with, and the Windows variant cleans dirs the Linux variant doesn't have. Neither references the other; both rely on a reviewer noticing that a new toolchain has appeared on the runner image and copy-pasting a `rm` line.

Public ecosystem context:

- `jlumbroso/free-disk-space` ([github.com/jlumbroso/free-disk-space](https://github.com/jlumbroso/free-disk-space)) is the de-facto disk-cleanup action on GitHub Actions, but it explicitly targets **Ubuntu only** — marketplace title is "Free Disk Space (Ubuntu)", and there is no Windows code path in `action.yml` ([source](https://github.com/jlumbroso/free-disk-space/blob/main/action.yml)).
- `endersonmenezes/free-disk-space`, `insightsengineering/disk-space-reclaimer`, and `easimon/maximize-build-disk-space` are all Linux-only.
- No widely-used composite action exists that handles both runner OSes from a single reference. The "Mastering Disk Space on GitHub Actions Runners" survey ([geraldonit.com](https://www.geraldonit.com/mastering-disk-space-on-github-actions-runners-a-deep-dive-into-cleanup-strategies-for-x64-and-arm64-runners/)) and the DEV "Squeezing Disk Space" guide ([dev.to/mathio](https://dev.to/mathio/squeezing-disk-space-from-github-actions-runners-an-engineers-guide-3pjg)) only cover Linux/x64+arm64.

This change is the first in this repo to take a position on the cross-platform contract.

## Goals / Non-Goals

**Goals:**

- One action reference `./.github/actions/clean-runner-disk` works on both `ubuntu-24.04` and `windows-2025` runners — workflows do not branch on OS.
- Windows cleanup completes in ≤ 4 minutes wall-clock on `windows-2025` (down from current ~10 min).
- Linux cleanup retains its current ~3-minute budget (no regression).
- A post-clean disk-free assertion makes a silent regression (cleanup script removed nothing) fail loudly rather than turning into a Docker-build OOM later in the job.
- The action emits one job-summary line per run (`"Freed X GB in Y seconds (runner: <os>)"`) so trend regressions are observable on the PR check page without opening logs.

**Non-Goals:**

- Caching the Windows base image (`mcr.microsoft.com/...`) or otherwise speeding up the `docker build` step itself. Separate change.
- Parallelizing the Docker build with vulnerability scanning (`docker/scout-action`). Separate change.
- Moving to self-hosted runners. Separate change.
- Supporting `macos-*` runners — the project does not run on macOS in CI; adding a path now would be speculative.
- Replacing the action with a third-party marketplace action — none cover both OSes (see Context).

## Decisions

### D1. Single composite action, OS-dispatched

**Decision**: One `action.yml` at `.github/actions/clean-runner-disk/`, with each step gated by `if: runner.os == 'Linux'` or `if: runner.os == 'Windows'`. Each step uses its native shell (`bash` for Linux, `pwsh`/`cmd` for Windows).

**Alternatives considered**:

- *Two actions, one per OS, kept as-is.* Rejected because it's the status quo and is exactly what allowed the drift this change is trying to fix.
- *One action that shells out to a per-OS script file (`clean-linux.sh`, `clean-windows.ps1`).* Considered. Better for unit-testing the scripts locally, worse for "open one file to see what the action does." We choose inline shells in `action.yml` for the first iteration. If the action grows past ~150 lines we revisit.
- *Use `jlumbroso/free-disk-space` for Linux and keep a custom Windows action.* Rejected — adds an external dependency, still leaves Windows separate, and we'd need to pin/audit a third-party action for every supply-chain review (this repo already runs the Scorecard workflow).

**Rationale**: Composite actions support OS-gated steps natively, and a single `action.yml` is what makes the cross-OS contract visible in one diff.

### D2. Windows fast-delete strategy: `cmd /c rmdir /s /q`, with PowerShell fallback

**Decision**: For each target directory on Windows, attempt removal via `cmd /c rmdir /s /q "<path>"` first. If the directory still exists afterward (long-path failure, locked file, ACL), fall back to `Remove-Item -LiteralPath <path> -Recurse -Force -ErrorAction Continue`. Both paths run inside the same PowerShell step so the fallback decision is per-directory.

**Alternatives considered**:

- *`robocopy /MIR <empty-dir> <target> /MT:128 /NFL /NDL /NJH /NJS`* — the canonical fastest empty-mirror trick. Considered. It's typically the winner on very large trees and parallelizes I/O across threads, but it's harder to read and has a non-standard exit-code convention (0–7 are "success-ish"). We adopt it only if `rmdir` benchmarks show it's not enough — recorded as Open Question 1.
- *Stay on `Remove-Item -Recurse -Force`* — the status quo. Rejected on measurement: ~10 minutes for 20 directories.
- *Use the `Microsoft.PowerShell.Management` `[System.IO.Directory]::Delete($path, $true)` .NET call* — same NTFS cost as `Remove-Item`; no win.

**Rationale**: `rmdir /s /q` issues fewer per-file syscalls than PowerShell's pipeline-based deletion and skips PowerShell's per-item provider overhead. We keep a PS fallback because `rmdir` doesn't traverse junctions/reparse points the same way and we don't want a previously-cleaned directory to silently remain.

### D3. Post-clean disk-free assertion

**Decision**: After cleanup, the action asserts free space on the build drive against a per-OS minimum (Linux: 20 GB on `/`, Windows: 40 GB on `C:`). Threshold below ⇒ `core.setFailed` with the actual number, so the job stops at the cleanup step rather than failing 15 minutes later in `docker build`.

**Alternatives considered**:

- *No assertion, rely on the build to fail.* Rejected — turns a 30-second cleanup misconfiguration into a 25-minute "no space left on device" rerun.
- *Assert "freed at least N GB" relative to pre-clean.* Rejected — the pre-clean baseline drifts every time GitHub updates the runner image, and we'd be alerting on noise rather than on actual breakage.

**Rationale**: A flat absolute threshold matches the question we actually care about ("can the Docker build run?"). Numbers are chosen as ~80% of the historically-observed free space after cleanup; they can be tuned via inputs without changing the spec.

### D4. Observability via `$GITHUB_STEP_SUMMARY`

**Decision**: The action writes one line to `$GITHUB_STEP_SUMMARY` (or the PowerShell equivalent on Windows) in the form `clean-runner-disk: freed 12.4 GB in 3m 12s on Windows`. This shows up on the PR check page in the job summary without needing to expand logs.

**Alternatives considered**:

- *Emit a metric to an external observability backend.* Out of scope — the repo has no metrics pipeline today.
- *No summary, rely on log timing.* Rejected because the user's research question that motivated this change required scraping `gh run view` JSON to discover the bottleneck. A one-line summary makes the same data visible at a glance.

### D5. Spec capability scope

**Decision**: New capability `ci-runner-disk-cleanup`. The capability's requirements are stated in terms of what a *CI engineer reviewing PR check timings* observes (job duration, post-clean free space, single action reference), not in terms of `rmdir` vs `Remove-Item`. The latter belongs in this design document; the former in the spec.

**Rationale**: Implementation tactics will rot (`rmdir` may stop being the fastest tool when GitHub upgrades the runner image, or when we move to Windows Server 2026). The contract — "≤ 4 min, ≥ 40 GB free, same action reference for both OSes" — is what we want to outlive the implementation.

## Risks / Trade-offs

- **[Risk] `rmdir /s /q` fails to remove a path that `Remove-Item` would have removed** (long-path > 260 chars, reparse points, ACL'd dirs). → **Mitigation**: per-directory PowerShell fallback in the same step; post-clean directory-existence check logs anything still present as a warning so we can iterate.
- **[Risk] GitHub updates `windows-2025` runner image to add a new pre-installed toolchain that fills the drive again.** → **Mitigation**: post-clean free-space assertion (D3) fails the job loudly; the failure message names the directory that grew. Linux side has the same protection.
- **[Risk] Inline shell scripts in `action.yml` become unmaintainable** as the cleanup list grows. → **Mitigation**: design contract requires splitting to `clean-linux.sh` / `clean-windows.ps1` once the action exceeds ~150 lines (see D1 alternatives). For now, both fit comfortably.
- **[Risk] A workflow that doesn't actually need cleanup pays the time cost** because cleanup is invoked unconditionally before the build. → **Mitigation**: action is only referenced from the three workflow jobs that do need it (`ci.yml`, `build.yml/test_image`, `windows.yml/test_windows`); the small/fast workflows (`gx`, `scorecard`, `tag`, `changelog`, `update_version`) don't call it and don't need to.
- **[Trade-off] Single composite action means the same `action.yml` runs steps that are no-ops on the other OS.** Each step is gated by `runner.os` so it costs the runner ~1 second per skipped step. Acceptable cost for the readability win of one file.
- **[Trade-off] PowerShell fallback means the worst-case Windows time is bounded by the slow path, not the fast path.** If `rmdir` fails on every directory, we're back to ~10 minutes. The post-clean assertion still fires, so the job fails fast rather than silently slow.

## Automated Test Strategy

- **Critical path**: PR runs of `windows.yml` and `build.yml` after the change is merged are the real test — both must complete and the Windows job must drop to ≤ 19 min median over a 10-PR sample.
- **Pre-merge verification**: a `workflow_dispatch` smoke run of each workflow on a PR branch validates the new action before merge. The action's post-clean assertion (D3) gives an immediate pass/fail without needing to wait for the Docker build to OOM.
- **No new test infrastructure**: composite actions are not unit-testable in isolation through GitHub's tooling; the verification surface is the workflow run itself. We accept this.
- **Regression guard**: the job-summary line (D4) captures duration and freed bytes per run. After merge, a 10-run window from `gh run list --workflow=windows.yml --json` is the metric to compare against the pre-change baseline (median ~25 min, p95 ~50 min) — recorded in `tasks.md` as the closure check.

## Observability

- **Primary signal**: `$GITHUB_STEP_SUMMARY` line per run — `"clean-runner-disk: freed X GB in Y on <os>"`. Visible on the PR check page without opening the log.
- **Failure surface**: post-clean assertion (D3) fails with a typed message (`"clean-runner-disk: only N GB free on <drive>, expected ≥ M GB. Largest remaining dirs: …"`) so a regression cannot be silent — the job either drops below threshold and fails immediately, or proceeds to a Docker build that has the space it needs.
- **Logging**: pre- and post-clean disk usage tables (already present in both existing actions) are preserved; nothing is silenced.
- **Out of band**: no Slack/email/metrics-backend integration. The repo has no such pipeline today and adding one is out of scope.

## Migration Plan

1. Land the unified action and update the three workflow references in the same PR — there is no period where one runner uses the new action and another uses the old. Composite-action callers are local to this repo, so there is no external migration cost.
2. Delete `.github/actions/clean-runner-disk-windows/` in the same PR. No tag / release implication.
3. Roll back, if needed, by reverting the single commit — both old action directories are recoverable from history.

## Open Questions

1. **Does `rmdir /s /q` actually beat `Remove-Item` by enough on `windows-2025`?** No first-party benchmark exists in the web sources surveyed. Tasks include a one-shot `workflow_dispatch` measurement before committing to the implementation; if the win is < 3 minutes, escalate to `robocopy /MIR` (D2 alternative).
2. **Should the `paths` input accept globs?** Current proposal is plain newline-separated absolute paths. Globs would need separate Bash and PowerShell expansion logic. Defer until a caller actually needs it — YAGNI.
3. **Do we want a `dry-run` input** so a workflow can preview what would be removed without removing it? Tempting for debugging the runner-image-update breakage scenario (Risk #2), but adds surface area. Defer until that scenario actually happens.
