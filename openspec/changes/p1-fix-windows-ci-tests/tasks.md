## 1. Fix the broken Dockerfile copy and Pester typo

- [ ] 1.1 In `windows.Dockerfile`, change the `COPY ./test/Windows.Tests.ps1` line to source `./test/windows/Windows.Tests.ps1`; keep the destination `.\test\Windows.Tests.ps1`.
- [ ] 1.2 In `test/windows/Windows.Tests.ps1`, change the CMake assertion pattern from `,versiona*` to `,version=*`. Apply the same `,version=*` form to the Win11SDK and VCTools assertions for consistency.

## 2. Make the test stage self-running

- [ ] 2.1 In `windows.Dockerfile`, replace the trailing `# CMD Invoke-Pester ...` comment in the `test` stage with `CMD ["powershell", "-NoLogo", "-NoProfile", "-File", ".\\script\\RunPester.ps1"]` (or equivalent that invokes `RunPester.ps1`).
- [ ] 2.2 Verify locally that `docker compose run --rm windows-test` runs Pester and exits with the Pester exit code. (Skip if no Windows host available; rely on the CI run for confirmation.)

## 3. Add the Flutter version Pester test

- [ ] 3.1 In `windows.Dockerfile`'s `test` stage, add `COPY ./config/version.json .\config\version.json` so the manifest is available at test time.
- [ ] 3.2 In `test/windows/Windows.Tests.ps1`, add a new `Describe "Flutter version"` block with a test that:
  - reads `config\version.json` via `Get-Content | ConvertFrom-Json`;
  - extracts `flutter.version`;
  - runs `flutter --version` and parses the first line into a semver string;
  - asserts the parsed version equals the manifest version, with a failure message naming both values.

## 4. Add the `flutter doctor` smoke test

- [ ] 4.1 In `test/windows/Windows.Tests.ps1`, add a `Describe "Flutter doctor"` block that runs `flutter doctor` and captures stdout.
- [ ] 4.2 Implement a parser that fails the test on any line starting with `[✗]`, except where the platform header is one of: `Android`, `iOS`, `macOS`, `Linux`, `Web`, `Chrome` (these platforms are intentionally disabled in `flutter config`).
- [ ] 4.3 The test passes when at least the `Windows Version` and `Visual Studio - develop Windows apps` lines are tagged `[✓]`.

## 5. Delete the dead Go/dockertest harness

- [ ] 5.1 Delete `test/windows/main.go`, `test/windows/main_test.go`, `test/windows/go.mod`, `test/windows/go.sum`.
- [ ] 5.2 Confirm that no workflow under `.github/workflows/` still references Go or `dockertest` (`grep -r "dockertest\|go test\|go mod" .github/workflows/`).

## 6. Clean up commented-out workflow blocks

- [ ] 6.1 In `.github/workflows/windows.yml`, delete the commented-out `Scan with Docker Scout` step block.
- [ ] 6.2 In `.github/workflows/windows.yml`, delete the commented-out `Push to Docker Hub` step block (release path is the subject of `p2-release-windows-image`).
- [ ] 6.3 In `.github/workflows/windows.yml`, delete the commented-out `validate_version` job block (it references the deleted `config/version.cue`).

## 7. Verify and ship

- [ ] 7.1 Push the branch; wait for the `test_windows` job in `.github/workflows/windows.yml` to complete on `windows-2025`.
- [ ] 7.2 Confirm the job exits 0 with all Pester tests reporting `Passed`.
- [ ] 7.3 Update PR #339 (or open a replacement) with a non-empty body referencing this proposal: link to `openspec/changes/p1-fix-windows-ci-tests/proposal.md` and list the assertions now enforced.
- [ ] 7.4 Merge.

## 8. Archive

- [ ] 8.1 After merge, archive this change by running the `openspec-archive-change` flow so the `windows-image-testing` spec is promoted to `openspec/specs/windows-image-testing/spec.md`.
