## 1. Benchmark the fast-delete path before committing to it

- [x] 1.1 Open a throwaway PR with a temporary `workflow_dispatch` job on `windows-2025` that runs both paths against a copy of one large target directory (`C:\hostedtoolcache`) — `Remove-Item -Recurse -Force` on one side, `cmd /c rmdir /s /q` on the other. Record wall-clock for each.
- [ ] 1.2 If `rmdir` is < 3 minutes faster than the PS baseline across two runs, drop the implementation back to design Open Question 1 and try `robocopy /MIR <empty> <target> /MT:128 /NFL /NDL /NJH /NJS`. Otherwise proceed with `rmdir` (D2).
- [ ] 1.3 Delete the benchmark workflow job; keep the measured numbers in the PR description for future regression comparison.

## 2. Build the unified composite action

- [ ] 2.1 Create `.github/actions/clean-runner-disk/action.yml` with `name`, `description`, and `runs.using: composite`.
- [ ] 2.2 Add an early step that rejects unsupported runner OSes (`if: runner.os != 'Linux' && runner.os != 'Windows'`) with `core.setFailed` naming the actual OS — satisfies spec scenario "Unsupported runner OS is rejected loudly".
- [ ] 2.3 Port the existing Linux cleanup script into the action, each step gated `if: runner.os == 'Linux'`, `shell: bash`. Preserve the full removal list from `.github/actions/clean-runner-disk/action.yml@HEAD` (no behavior regression) — satisfies spec requirement "Linux cleanup retains its current ~3-minute budget".
- [ ] 2.4 Add a Windows cleanup step gated `if: runner.os == 'Windows'`, `shell: pwsh`, that iterates the target paths and tries `cmd /c rmdir /s /q "$p"` first, then falls back to `Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Continue` if the directory still exists. Reuse the path list from `.github/actions/clean-runner-disk-windows/action.yml@HEAD`.
- [ ] 2.5 Add pre-clean and post-clean disk-usage logging steps for both OSes (preserve current `df -h` / `Get-PSDrive` output).
- [ ] 2.6 Add the post-clean free-space assertion: Linux ≥ 20 GB free on `/`, Windows ≥ 40 GB free on `C:`. On failure, `core.setFailed` with a message naming actual free, threshold, and top-5 remaining dirs by size — satisfies spec requirement "Action asserts minimum post-clean free space".
- [ ] 2.7 Add the job-summary line emission: append `clean-runner-disk: freed X GB in Ym Zs on <os>` to `$GITHUB_STEP_SUMMARY` (both branches), emitted even when the assertion fails — satisfies spec requirement "Action emits a one-line job summary".

## 3. Switch workflows to the unified action

- [ ] 3.1 Update `.github/workflows/ci.yml:50-51` to reference the unified action (path unchanged; behavior unchanged on Linux).
- [ ] 3.2 Update `.github/workflows/build.yml:41-42` to reference the unified action.
- [ ] 3.3 Update `.github/workflows/windows.yml:23-24` to reference `./.github/actions/clean-runner-disk` (was `clean-runner-disk-windows`).

## 4. Remove the old Windows-only action

- [ ] 4.1 Delete `.github/actions/clean-runner-disk-windows/action.yml` and its parent directory.
- [ ] 4.2 Grep the repo for any other references to `clean-runner-disk-windows` (docs, READMEs, scripts). Update or remove them.

## 5. Verify on a real PR before merge

- [ ] 5.1 Push the change as a draft PR. Confirm `windows.yml/test_windows` completes successfully and the summary line appears on the run page.
- [ ] 5.2 Confirm `build.yml/test_image` and `ci.yml/test_image` complete successfully and the summary line appears.
- [ ] 5.3 Record the duration of each cleanup step from the PR run in the PR description as the pre-merge baseline for post-merge comparison.

## 6. Post-merge closure check

- [ ] 6.1 After 10 post-merge runs of `windows.yml`, run `gh run list --workflow=windows.yml --limit 20 --status completed --json databaseId,createdAt,updatedAt | jq` and confirm the median total job duration is ≤ 19 minutes (down from ~25). If not, reopen with the recorded numbers and revisit design Open Question 1.
- [ ] 6.2 After 10 post-merge runs of `ci.yml`, confirm Linux job duration has not regressed by more than 30 seconds versus the pre-change median (~10.8 min). If it has, investigate immediately — Linux regression is a non-goal of this change.
