## 1. Build the unified composite action

- [x] 1.1 Create `.github/actions/clean-runner-disk/action.yml` with `name`, `description`, and `runs.using: composite`.
- [x] 1.2 Add an early step that rejects unsupported runner OSes (`if: runner.os != 'Linux' && runner.os != 'Windows'`) with `core.setFailed` naming the actual OS — satisfies spec scenario "Unsupported runner OS is rejected loudly".
- [x] 1.3 Port the existing Linux cleanup script into the action, each step gated `if: runner.os == 'Linux'`, `shell: bash`. Preserve the full removal list from `.github/actions/clean-runner-disk/action.yml@HEAD` (no behavior regression) — satisfies spec requirement "Linux cleanup retains its current ~3-minute budget".
- [x] 1.4 Add a Windows cleanup step gated `if: runner.os == 'Windows'`, `shell: pwsh`, that creates an empty source directory once and iterates the target paths invoking `robocopy <empty> <target> /MIR /MT:128 /R:1 /W:1 /NFL /NDL /NJH /NJS`, treating `$LASTEXITCODE -lt 8` as success, then `Remove-Item -LiteralPath <target> -Force` on the now-empty directory. For any target where robocopy returns `$LASTEXITCODE -ge 8`, fall back to `Remove-Item -LiteralPath <target> -Recurse -Force -ErrorAction Continue`. Reuse the path list from `.github/actions/clean-runner-disk-windows/action.yml@HEAD`.
- [x] 1.5 Add pre-clean and post-clean disk-usage logging steps for both OSes (preserve current `df -h` / `Get-PSDrive` output).
- [x] 1.6 Add the post-clean free-space assertion: Linux ≥ 20 GB free on `/`, Windows ≥ 40 GB free on `C:`. On failure, `core.setFailed` with a message naming actual free, threshold, and top-5 remaining dirs by size — satisfies spec requirement "Action asserts minimum post-clean free space".
- [x] 1.7 Add the job-summary line emission: append `clean-runner-disk: freed X GB in Ym Zs on <os>` to `$GITHUB_STEP_SUMMARY` (both branches), emitted even when the assertion fails — satisfies spec requirement "Action emits a one-line job summary".

## 2. Switch workflows to the unified action

- [x] 2.1 Update `.github/workflows/ci.yml:50-51` to reference the unified action (path unchanged; behavior unchanged on Linux). _No-op: reference already `./.github/actions/clean-runner-disk`._
- [x] 2.2 Update `.github/workflows/build.yml:41-42` to reference the unified action. _No-op: reference already `./.github/actions/clean-runner-disk`._
- [x] 2.3 Update `.github/workflows/windows.yml:23-24` to reference `./.github/actions/clean-runner-disk` (was `clean-runner-disk-windows`).

## 3. Remove the old Windows-only action

- [x] 3.1 Delete `.github/actions/clean-runner-disk-windows/action.yml` and its parent directory.
- [x] 3.2 Grep the repo for any other references to `clean-runner-disk-windows` (docs, READMEs, scripts). Update or remove them. _No other references outside OpenSpec artifacts describing this change._

## 4. Verify on a real PR before merge

- [x] 4.1 Push the change as a draft PR. Confirm `windows.yml/test_windows` completes successfully and the summary line appears on the run page. _Run 25763257213 (post-fix): success. Cleanup 301 s (5.0 min) vs 640 s baseline = -53%. Total job 29.5 min vs 35.8 min baseline. First PR run 25760891151 measured 1036 s cleanup (regression) and motivated the switch from robocopy to ForEach-Object -Parallel._
- [x] 4.2 Confirm `build.yml/test_image` and `ci.yml/test_image` complete successfully and the summary line appears. _Run 25763257210: cleanup 368 s (success), image built + tested. Job failed at "Scan with Docker Scout" with FORBIDDEN team-auth error — unrelated to this PR. ci.yml only runs on push to main; verification deferred to post-merge._
- [x] 4.3 Record the duration of each cleanup step from the PR run in the PR description as the pre-merge baseline for post-merge comparison. _Recorded in PR #448 comments (https://github.com/gmeligio/flutter-docker-image/pull/448#issuecomment-4435176986 has the final numbers)._

## 5. Post-merge closure check

- [x] 5.1 After 10 post-merge runs of `windows.yml`, confirm the median total job duration moved in the right direction versus the pre-change baseline. _Measured 17 post-merge successful runs (2026-05-13 → 2026-05-24, `gh run list --workflow=windows.yml --limit 30 --status success`): median ~29 min vs ~30.5 min pre-change baseline — only ~1.5 min total-job improvement despite the 5.7-min cleanup-step improvement (10.7 → 5.0 min, -53 %). The cleanup-step spec contract IS met; the original aspirational target of ≤ 19 min median total job is NOT met because the remaining wall-clock lives in `Test image and push`, which is out of scope for this change. Total-job improvement on `windows.yml` is handed off to a separate change targeting the build/test steps. See design.md Open Question 2._
- [x] 5.2 After 10 post-merge runs of `ci.yml`, confirm Linux job duration has not regressed by more than 30 seconds versus the pre-change median (~10.8 min). _Measured 12 post-merge successful runs (2026-05-13 → 2026-05-24): median ~10 min vs ~10.8 min pre-change baseline — no regression. Linux non-goal satisfied._
