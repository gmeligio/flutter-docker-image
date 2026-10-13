## 1. Switch runner labels

- [x] 1.1 Replace `runs-on: ubuntu-24.04` with `runs-on: ubuntu-26.04` in every workflow under `.github/workflows/`.
- [x] 1.2 Confirm no `ubuntu-24.04` label remains under `.github/`.

## 2. Adapt the Linux cleanup action

- [x] 2.1 Replace the version-specific LLVM paths with `/usr/lib/llvm-*`.
- [x] 2.2 Update the MongoDB comment to name `ubuntu-26.04`.

## 3. Keep large scratch writes off tmpfs /tmp

- [x] 3.1 Point the Docker Scout step's `TMPDIR` at `${{ runner.temp }}`, so `Scan image (flutter-android)` no longer fails with `disk quota exceeded` under `/tmp`.

## 4. Verify on the draft PR

- [ ] 4.1 `ci.yml` passes. The cleanup summary shows `≥ 20 GB free on /`, and the freed amount is within 2 GB of the 24.04 baseline (~38 GB).
- [ ] 4.2 The Linux cleanup step stays within the 2-minute budget.
- [ ] 4.3 `harden-runner` audit and the buildx-based image builds and digest lookups work on the new image.
- [ ] 4.4 Workflows the PR doesn't trigger (`update-version`, `update-docs`, `scorecard`, `cleanup-pr-image`, `gx`) pass on their next run or via `workflow_dispatch`.

## 5. Archive

- [ ] 5.1 After merge, archive this change and sync `openspec/specs/ci-runner-disk-cleanup/spec.md`.
