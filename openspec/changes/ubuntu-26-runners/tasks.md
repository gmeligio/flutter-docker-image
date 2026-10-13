## 1. Switch runner labels

- [x] 1.1 Replace `runs-on: ubuntu-24.04` with `runs-on: ubuntu-26.04` in every workflow under `.github/workflows/`.
- [x] 1.2 Confirm no `ubuntu-24.04` label remains under `.github/`.

## 2. Adapt the Linux cleanup action

- [x] 2.1 Replace the version-specific LLVM paths with `/usr/lib/llvm-*`.
- [x] 2.2 Update the MongoDB comment to name `ubuntu-26.04`.

## 3. Keep large scratch writes off tmpfs /tmp

- [x] 3.1 Point the Docker Scout step's `TMPDIR` at `${{ runner.temp }}`, so `Scan image (flutter-android)` no longer fails with `disk quota exceeded` under `/tmp`.

## 4. Verify on the draft PR

- [ ] 4.1 `ci.yml` passes. _Cleanup on 26.04 freed ~34 GB (24.04 baseline ~38 GB) and left 124 GB free._
- [ ] 4.2 The Linux cleanup step stays within the 2-minute budget. _When it ran on 26.04 it took 2m37s–4m06s; superseded by 5.4, which skips it when ≥ 30 GB is free._
- [ ] 4.3 `harden-runner` audit and the buildx-based image builds and digest lookups work on the new image.
- [ ] 4.4 Workflows the PR doesn't trigger (`update-version`, `update-docs`, `scorecard`, `cleanup-pr-image`, `gx`) pass on their next run or via `workflow_dispatch`.

## 5. Size the free-space minimum

- [x] 5.1 Add a temporary `Report disk usage after build` step to the `build.yml` image build and fork image test jobs, and to both `ci.yml` build jobs.
- [x] 5.2 Record the peak disk use per job, and pick the Linux free-space minimum from it. _`build.yml` android (push) ~9 GB, `ci.yml` android (load) ~12 GB, `ci.yml` linux (load) ~3.5 GB; fork path estimated ~23 GB. Minimum set to 30 GB._
- [x] 5.3 Remove the temporary step.
- [x] 5.4 Skip the Linux cleanup when `/` already has ≥ 30 GB free, and raise the post-clean assertion's Linux minimum to 30 GB.
- [x] 5.5 On the draft PR, confirm the Linux image builds log "skipping cleanup", the assertion passes, and the summary reports `freed 0.00 GB`. _`flutter-android` build on 70a2151: "90.03 GB already free on / (minimum 30 GB) — skipping cleanup", then "90.03 GB free on / (threshold 30 GB) — OK"; the step took under a second._

## 6. Archive

- [ ] 6.1 After merge, archive this change and sync `openspec/specs/ci-runner-disk-cleanup/spec.md`.
