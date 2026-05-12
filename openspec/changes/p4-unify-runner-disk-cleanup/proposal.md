## Why

The `test_windows` job in `.github/workflows/windows.yml` is the slowest job in CI by a wide margin: median ~25 min and worst-case ~50 min, roughly 2× the next slowest (`test_image` at ~21 min). Inside that job, the `Clean Runner Disk (Windows)` composite action alone consumes ~10 minutes — a third of the wall-clock budget — because it deletes ~20 large hosted-tool directories via PowerShell `Remove-Item -Recurse -Force`, which is the slow path on NTFS for millions of small files. Meanwhile the Linux equivalent at `.github/actions/clean-runner-disk/action.yml` does the same job in ~3 min using `apt-get remove` + `rm -rf`, and the two actions duplicate intent (free space so the Docker build doesn't fill the runner) with no shared contract. Maintaining two actions also drifts what each removes — e.g. the Linux action prunes Rust/Haskell/Julia/Swift, while the Windows action prunes a different set, and nothing enforces parity.

This change unifies both into a single CI capability with measurable performance and behavior requirements, and replaces the slow PowerShell path with a fast native-tool path (cmd `rmdir /s /q` or `robocopy` empty-mirror) so the Windows cleanup completes within a budgeted time.

## What Changes

- **New unified composite action** `.github/actions/clean-runner-disk/action.yml` that dispatches by `runner.os` and runs the platform-appropriate cleanup, replacing the per-OS pair.
- **BREAKING (for `.github/workflows/*.yml` callers only)**: remove `.github/actions/clean-runner-disk-windows/`; both `ci.yml` and `build.yml` `test_image` and `windows.yml` `test_windows` now reference the same action path `./.github/actions/clean-runner-disk`.
- Windows path swaps `Remove-Item -Recurse -Force` for `robocopy <empty> <target> /MIR /MT:128 /R:1 /W:1 /NFL /NDL /NJH /NJS` followed by an empty-directory `Remove-Item`. `robocopy /MT:128` is the only readily-available native tool that parallelizes per-file metadata cost on NTFS, which dominates wall-clock on directories with tens of thousands of small files (hostedtoolcache, msys64, Miniconda, Strawberry). PowerShell `Remove-Item -Recurse -Force` remains the per-directory fallback when robocopy returns an exit code ≥ 8. Target: Windows cleanup completes in ≤ 4 minutes wall-clock.
- Both paths log disk usage before and after, and the action surfaces a job-summary line ("Freed X GB in Y seconds") so regressions in CI duration are visible without scraping logs.
- Action accepts an optional `paths` input (newline-separated) so individual workflows can opt in/out of specific aggressive deletions if needed (e.g. a future job that wants to keep Android SDK on the host).
- Drift-protection: the action documents the intent ("free ≥ N GB of space without touching anything the Flutter build needs") and the two OS-specific cleanup scripts live as siblings inside the single action directory, so a reviewer sees both in one diff.

## Capabilities

### New Capabilities

- `ci-runner-disk-cleanup`: defines what `.github/actions/clean-runner-disk` SHALL achieve on the GitHub-hosted runners used by this repo (`ubuntu-24.04` and `windows-2025`) — minimum disk freed, maximum wall-clock spent, observability of the result, and the contract that both runner OSes are invoked via the same action reference from any workflow that needs cleanup.

### Modified Capabilities

_None._ The existing specs (`actions-version-tracking`, `flutter-version-update`, `repository-wiki`, `windows-image-testing`) describe what the images and their CI verify, not the CI infrastructure that supports the build. This change introduces a brand-new capability rather than redefining any of them.

## Impact

- **Affected files**:
  - New: `.github/actions/clean-runner-disk/action.yml` (replacing the current Linux-only file at the same path)
  - Possibly new: `.github/actions/clean-runner-disk/clean-linux.sh`, `clean-windows.ps1` or `clean-windows.cmd` (split for readability; final layout decided in design)
  - Removed: `.github/actions/clean-runner-disk-windows/action.yml` and its directory
  - Updated callers: `.github/workflows/ci.yml:50-51`, `.github/workflows/build.yml:41-42`, `.github/workflows/windows.yml:23-24`
- **Behavioral change for CI**: median `test_windows` wall-clock drops by ~6 minutes (from ~25 to ~19) — directly observable on the PR check timeline. No change to what is actually freed from the runner; the contract is "at least the same disk space, faster."
- **Risk**: `robocopy` returns exit codes 0–7 for various success cases (1=copied, 2=purged, 4=mismatched, etc.); only ≥ 8 is a real failure. Mitigation: explicitly treat `$LASTEXITCODE -lt 8` as success, keep a per-directory PowerShell `Remove-Item` fallback for the ≥ 8 case, and assert post-clean free space against a minimum threshold so a silent regression in what gets removed fails the job rather than being discovered as a downstream build OOM.
- **Out of scope**: caching the Windows base image layer (separate change), parallelizing build + scan (separate change), self-hosted runners (separate change). This proposal addresses only the cleanup step.
- **Relevance gate**: a CI engineer reviewing a PR for this repo would notice that every PR's Windows check takes ~10 min less, and would observe the unified action when scanning the diff for cleanup behavior. The spec captures the contract that prevents the Windows path from drifting back to "delete everything in PowerShell because it's the obvious thing to write."
