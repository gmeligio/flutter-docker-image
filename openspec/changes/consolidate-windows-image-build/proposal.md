## Why

The Windows image is built in two places — `windows.yml` (PR test, `--target test`) and `release.yml`'s `release-windows` job (tag publish, `--target flutter`) — that share ~80% of their steps but have **drifted**: the PR job cleans the runner disk and starts the Docker daemon, the release job does neither. That drift is a live production bug — release run 27745938452 died installing VS Build Tools with `There is not enough space on the disk` because `release-windows` never ran `clean-runner-disk`, and `windows-2025` now ships only ~33 GB free after the `D:` drive removal. Neither Windows job runs `harden-runner`, which `ci-workflow-hardening` already requires of every job (it was previously impossible on Windows; `harden-runner` shipped Windows support in early 2026). Consolidating the shared build into one definition fixes the OOM, closes the hardening gap, and removes the ability for the two paths to drift again.

## What Changes

- **NEW — `.github/workflows/windows-image.yml`, a `workflow_call` reusable workflow** that owns the entire shared Windows build: `harden-runner` (first step) → checkout → `clean-runner-disk` → ensure-Docker-daemon → read version manifest → `docker/metadata-action` → registry logins → `docker build windows.Dockerfile` with the five build-args (`flutter_version`, `git_version`, `vs_cmake_version`, `vs_win11sdk_build`, `vs_vctools_version`). Inputs: `target`, `push` (boolean), `can-login` (boolean, fork-safe). The post-build tail branches on `push`: run the Pester suite (test) or push the tags to all three registries (release).
- **BREAKING — `windows.yml` becomes a thin caller.** Its `test-windows` job is replaced by a `uses: ./.github/workflows/windows-image.yml` call with `target: test`, `push: false`, `can-login: <not a fork>`, `secrets: inherit`. The inline build/cleanup/daemon/login/test steps are removed.
- **BREAKING — `release-windows` becomes a thin caller.** Replaced by a `uses: ./.github/workflows/windows-image.yml` call with `target: flutter`, `push: true`, `can-login: true`, `secrets: inherit`, and `permissions: { contents: read, packages: write }` on the caller job. This is what adds disk cleanup + daemon guard + harden-runner to the release path.
- **Fork-PR safety preserved.** Docker Hub login is gated on `can-login`; GHCR and Quay logins are gated on `push`. A fork PR (no secrets) builds and tests without attempting any login.
- **Harden-runner reaches the Windows path** for the first time, via the shared workflow's job — satisfying `ci-workflow-hardening` for both Windows jobs at once.

## Capabilities

### New Capabilities

- `windows-image-build`: the single reusable (`workflow_call`) workflow that builds `windows.Dockerfile`. Owns the shared contract both Windows paths depend on — harden-runner first, runner disk cleanup before build, Docker daemon readiness, the five build-args, fork-safe and push-gated registry logins — parameterized by `target`/`push`/`can-login` so the PR-test and release callers stay byte-identical in everything but their post-build tail.

### Modified Capabilities

- `windows-image-testing`: the PR check is now produced by a caller job that delegates to `windows-image-build` with `target: test`; the requirement that every PR builds `--target test` and runs Pester on `windows-2025` is preserved but expressed through the shared workflow rather than inline steps.
- `windows-image-release`: the tag-push publish is now produced by a caller job that delegates to `windows-image-build` with `target: flutter`, `push: true`; the three-registry fan-out, parallel-with-Android execution, `workflow_dispatch` Windows-only rebuild, and OCI-label conventions are all preserved, and the release path now additionally runs `clean-runner-disk` (fixing the OOM) and `harden-runner`.
- `ci-workflow-hardening`: the "every job starts with harden-runner" requirement is restated to account for reusable-workflow caller jobs — a `uses:` caller job runs no steps, so harden-runner SHALL be the first step of the *called* workflow's job; the Windows path is now in compliance.

## Impact

- **New file:** `.github/workflows/windows-image.yml` (reusable workflow).
- **Modified workflows:** `.github/workflows/windows.yml` (job → caller), `.github/workflows/release.yml` (`release-windows` job → caller, with `packages: write` retained at job level).
- **No Dockerfile change:** `windows.Dockerfile` and the five build-args are unchanged; the build command moves verbatim into the reusable workflow.
- **Reuses existing capabilities unchanged:** `.github/actions/clean-runner-disk` (already invocable on `windows-2025`) and `script/setEnvironmentVariables.js`.
- **Security/governance:** brings both Windows jobs into `ci-workflow-hardening` compliance for harden-runner; `gx lint` policy and SHA-pinning rules apply to the new workflow file.
- **Relevance gate:** passes — this changes spec-level behavior observed by the CI engineer cutting a release (the Windows image now publishes instead of OOM-ing) and by the maintainer reviewing workflows (one Windows build definition, harden-runner present), and it removes a defect that reddens the release run on every Flutter bump.
