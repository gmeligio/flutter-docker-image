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

### D2. Windows fast-delete strategy: PowerShell `ForEach-Object -Parallel` over `Remove-Item`

**Decision**: One PowerShell 7 step iterates the target paths through `ForEach-Object -Parallel { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction Continue } -ThrottleLimit 8`. Concurrency comes from the parallel runspaces, not from a subprocess like `robocopy`. A residual `Test-Path` check after each removal logs a warning (`::warning::<path> still present after removal`) so silent failures are visible. The post-clean free-space assertion in D3 is the contract that catches a regression in what got removed.

**Pivot from robocopy** (the original D2 proposal): we first shipped `robocopy <empty-dir> <target> /MIR /MT:128 /R:1 /W:1 /NFL /NDL /NJH /NJS` followed by an empty-directory `Remove-Item`, with a `Remove-Item -Recurse` fallback for `$LASTEXITCODE -ge 8`. The first PR run measured the cleanup step at **1036 s — a 62 % regression** vs the 640 s baseline. Re-running the same workflow with `ForEach-Object -Parallel -ThrottleLimit 8` over `Remove-Item` dropped cleanup to **301 s** (-53 % vs baseline). The public benchmarks we used to justify robocopy (HN threads, mattpilz.com) measured cold filesystems on local hardware; the GitHub-hosted `windows-2025` runner has Defender real-time scanning on every file open, which appears to penalize robocopy's per-file open+stat+set-attributes sequence more than it penalizes a single `Remove-Item` traversal. PR #448 ([comment](https://github.com/gmeligio/flutter-docker-image/pull/448#issuecomment-4435176986)) records the measurement.

**Alternatives considered**:

- *`robocopy /MIR /MT:128`* — the original choice, ruled out by the measurement above. Not adopted.
- *`cmd /c rmdir /s /q "<path>"`* — single-threaded recursive remove. Not measured against the parallel `Remove-Item` because the latter already beat the baseline by 53 % and adding a serial fallback only helps if the parallel path fails. The `Test-Path` post-check + post-clean assertion (D3) is the safety net instead.
- *Stay on serial `Remove-Item -Recurse -Force`* — the 640 s baseline. Beaten by the parallel variant.
- *`[System.IO.Directory]::Delete($path, $true)`* — same per-file NTFS cost as `Remove-Item`; no win.
- *Combo `del /F /Q /S` then `rmdir /S /Q`* (Pilz recipe at [mattpilz.com](https://mattpilz.com/fastest-way-to-delete-large-folders-windows/)) — single-threaded; superseded by the parallel-runspace approach.

**Rationale**: The 20-directory cleanup list contains several trees (`C:\hostedtoolcache`, `C:\msys64`, `C:\Miniconda`, `C:\Strawberry`) that are individually 1–5 GB with tens of thousands of small files. Wall-clock is dominated by per-file syscalls, and PowerShell 7's `ForEach-Object -Parallel` removes 8 trees concurrently in-process without paying robocopy's per-file overhead. `ThrottleLimit 8` was chosen empirically — it kept I/O pressure within what the runner tolerated without escalating Defender contention.

**Why no explicit fallback chain**: each `Remove-Item` invocation runs with `-ErrorAction Continue`, so a single locked file inside a tree does not abort the whole removal. The `Test-Path` post-check emits a `::warning::` per path that did not fully clear, and the D3 free-space assertion fails the step if too much survived. Adding a `cmd /c rmdir` or `robocopy` fallback would only matter if the parallel path catastrophically failed; in practice it has not, and a dead fallback path would rot. If we ever see a real failure surface, the warning log will name the directory.

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

- **[Risk] A specific tree resists `Remove-Item` even with `-Force`** (locked files held by Defender mid-scan, reparse points, ACL'd files, paths > 260 chars). → **Mitigation**: each parallel runspace uses `-ErrorAction Continue` so the whole step doesn't abort on one failure; a `Test-Path` post-check emits `::warning::<path> still present after removal` per surviving directory; and the D3 free-space assertion fails the step if too much survived. No silent regression possible.
- **[Risk] GitHub updates `windows-2025` runner image to add a new pre-installed toolchain that fills the drive again.** → **Mitigation**: post-clean free-space assertion (D3) fails the job loudly; the failure message names the directory that grew. Linux side has the same protection.
- **[Risk] Inline shell scripts in `action.yml` become unmaintainable** as the cleanup list grows. → **Mitigation**: design contract requires splitting to `clean-linux.sh` / `clean-windows.ps1` once the action exceeds ~150 lines (see D1 alternatives). For now, both fit comfortably.
- **[Risk] A workflow that doesn't actually need cleanup pays the time cost** because cleanup is invoked unconditionally before the build. → **Mitigation**: action is only referenced from the three workflow jobs that do need it (`ci.yml`, `build.yml/test_image`, `windows.yml/test_windows`); the small/fast workflows (`gx`, `scorecard`, `tag`, `changelog`, `update_version`) don't call it and don't need to.
- **[Trade-off] Single composite action means the same `action.yml` runs steps that are no-ops on the other OS.** Each step is gated by `runner.os` so it costs the runner ~1 second per skipped step. Acceptable cost for the readability win of one file.
- **[Trade-off] `ThrottleLimit 8` is empirical, not derived.** A larger value (16, 32) might be faster on the runner but raises Defender contention; a smaller value (4) is safer but slower. The chosen value put cleanup at 5.0 min on the verification run, which is over the 4-min design target but well under the 10.7-min baseline. Tuning is left for a follow-up if the post-merge p95 trends back up.

- **[Trade-off] Cleanup-step wins did not fully propagate to total job duration.** Cleanup dropped 10.7 → 5.0 min, but post-merge median for `windows.yml` total job duration sits at ~29 min versus the ~30.5 min pre-change baseline — most of the cleanup savings were absorbed by `Test image and push` variance. The cleanup-step spec contract is met; the total-job improvement is bounded by what cleanup alone can do, and further wins on `windows.yml` belong to a separate change targeting the build/test steps.

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

1. **~~Does `rmdir /s /q` or `robocopy /MIR /MT:128` beat `Remove-Item` on `windows-2025`?~~** Resolved by first-party measurement during verification (PR #448): `robocopy /MIR /MT:128` regressed cleanup to 1036 s (vs 640 s baseline) on the GitHub-hosted runner, contradicting public benchmarks that motivated the original D2 choice. Pivoted to PowerShell 7 `ForEach-Object -Parallel` over `Remove-Item -Recurse -Force` with `ThrottleLimit 8`, which dropped cleanup to 301 s (-53 % vs baseline). `rmdir /s /q` was not measured because the parallel `Remove-Item` already hit the design intent; if a future regression re-opens this question, `cmd /c rmdir /s /q` is the next candidate.

2. **~~Does the cleanup improvement translate to total-job improvement on `windows.yml`?~~** Resolved-as-no: post-merge median total job duration is ~29 min vs ~30.5 min pre-change baseline — only ~1.5 min off total, not the ~6 min off cleanup. The remaining time lives in `Test image and push`, which is out of scope for this change. Closure check 5.1 ("median ≤ 19 min over 10 post-merge runs") was an aspirational consequence and is not met; the cleanup-step contract IS met. Total-job improvement on `windows.yml` is handed off to a separate change.
2. **Should the `paths` input accept globs?** Current proposal is plain newline-separated absolute paths. Globs would need separate Bash and PowerShell expansion logic. Defer until a caller actually needs it — YAGNI.
3. **Do we want a `dry-run` input** so a workflow can preview what would be removed without removing it? Tempting for debugging the runner-image-update breakage scenario (Risk #2), but adds surface area. Defer until that scenario actually happens.
