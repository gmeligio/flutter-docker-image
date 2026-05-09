## Context

PR #339 has 11 commits over ~12 months and is currently in a state where the Windows CI job either fails the `COPY` step or never produces meaningful signal. The accumulated changes overlap three concerns: (1) fixing the test pipeline, (2) adding a Go-based dockertest harness, (3) renaming `script/test.sh` files. This change keeps only (1). It treats Pester running *inside* the test-target container as the single verification mechanism for the Windows image, mirroring how the Android image uses `container-structure-test`.

Constraints:

- `windows-2025` is the only viable runner. There is no Windows-container support in `docker/build-push-action`, no Buildx cache, and the full image build (Flutter clone + VS BuildTools install) takes 30–60 minutes per run.
- The `gx`-managed action pinning regime (commit `846ffd6`, spec `actions-version-tracking`) requires every `uses:` to be SHA-pinned with a `# vX.Y.Z` comment. New actions added to `windows.yml` must go through `.github/gx.toml`.
- `config/version.json` is the single source of truth for `flutter.version` (spec `flutter-version-update`). The Pester suite must read it, not hardcode.

## Goals / Non-Goals

**Goals:**

- The `test_windows` PR check goes from "in_progress forever / red on COPY" to "green on a healthy image, red on a regression."
- The Pester suite has at least one positive assertion on Flutter behavior (version, doctor) rather than only inspecting the on-disk VS package directories.
- `test/windows/` contains exactly one form of test (Pester). No dead skeletons.
- Everything that PR #339 added but did not finish is either finished or removed; nothing is left in a half-implemented state.

**Non-Goals:**

- Publishing the `flutter-windows` image on tag (covered by `p2-release-windows-image`).
- Tracking the VS BuildTools / Win11 SDK / CMake versions in `config/version.json` and through Renovate (covered by `p3-windows-version-schema`).
- Reducing the Windows CI run time. The job will remain slow; this change accepts that.
- Adding Docker Scout vulnerability scanning for the Windows image. The commented-out block is deleted; reintroducing it is left to a separate change if/when Scout becomes valuable for the Windows base image.
- Adding the `validate_version` job to `windows.yml`. The same CUE validation runs in `build.yml`'s `validate_version_files` job already; duplicating it on `windows-2025` adds runner cost with no new signal.

## Decisions

### Decision: Pester is the only verification harness; the Go/dockertest skeleton is deleted

The Go module under `test/windows/` (commit `df7666e`) is removed in this change. Reasons:

- It is not invoked by any CI workflow.
- Its only useful assertion (the Pester `Exec` block in `main_test.go:38-49`) is commented out.
- It runs the test image as `flutter-docker-image-windows-test:latest` without ever building it, so even uncommented it would fail.
- Pester running *inside* the container is the natural fit: the assertions are about the file system and toolchain *of the container*, which is awkward to express through `dockertest.Exec` from a Linux Go process.

Alternatives considered:

- **Wire the Go harness into CI.** Rejected: doubles the test infrastructure for no new signal, and the harness would still need a Windows host to run Windows containers — the same `windows-2025` runner constraint.
- **Keep the harness as a placeholder.** Rejected: dead code rots; unmaintained `go.mod` will collect `govulncheck` noise from Renovate.

### Decision: The Flutter version assertion reads `config/version.json` at test time, not via a build arg

The Pester test computes the expected version by parsing `config/version.json` (already `COPY`'d into the test stage as part of the `flutter` stage's checkout, or freshly copied in the `test` stage). Alternatives:

- **Hardcode the version in the test.** Rejected: drifts on every Flutter upgrade; defeats the point of `flutter-version-update`.
- **Pass via `--build-arg expected_flutter_version` and bake into env.** Rejected: extra plumbing; the `flutter_version` build arg is already the source of truth fed to `git clone --branch`. Reading the manifest directly catches the case where someone passes a build arg that doesn't match the manifest.

### Decision: `flutter doctor` failure mode

`flutter doctor` produces lines like `[✓]`, `[!]`, `[✗]`. The test fails only on `[✗]` lines. Lines tagged `[!]` are warnings (e.g., "Android Studio not installed") and are expected on this image since most platforms are explicitly disabled by `flutter config`. Lines for disabled platforms (`Android`, `iOS`, `macOS`, `Linux`, `Web`, `Chrome`) are skipped entirely by parsing the platform header.

### Decision: VS component pattern fix uses `,version=*`

The on-disk format for VS package directories is `<ComponentId>,version=<X.Y.Z.W>`. The current pattern `,versiona*` is a typo. The pattern `,version=*` is the minimum specific match that distinguishes a real install directory from any other coincident directory. Using `*` alone (no `,version=` anchor) would accept directories like `Microsoft.VisualStudio.Component.VC.CMake.Project_alt,…` which is too loose.

### Decision: `CMD` in the test stage points at `RunPester.ps1`

`CMD` is added so `docker run <test-image>` runs the suite without arguments. The CI workflow continues to pass `.\script\RunPester.ps1` as an explicit argument; this is redundant but harmless. The reason for keeping the explicit argument in CI is that some Windows image base layers reset `CMD`, and the explicit invocation is robust to that.

## Risks / Trade-offs

- **[Risk] Build duration on `windows-2025` may exceed the GitHub Actions timeout for free-tier runners.** → Mitigation: this repo is not free-tier-constrained (see `release_android` already running multi-job pipelines). The `concurrency` block in `windows.yml` cancels stale runs so a force-push doesn't queue multiple builds. No further mitigation in this change; if duration becomes a blocker, layer caching in a follow-up.
- **[Risk] `flutter doctor` output format is not a stable contract; Flutter could change `[✗]` to a different marker.** → Mitigation: the doctor parser is small and lives in the Pester test, so a Flutter upgrade that breaks it produces a single, localized red test rather than silent passes. The `flutter-version-update` spec already requires a passing CI before merge, so any format break is caught at upgrade time, not in production.
- **[Trade-off] Removing the Go harness is a one-way door** for any future contributor who wants to add Linux-host-driven dockertest assertions. → Acceptable: such a future contributor can re-add the module deliberately, against a real requirement, instead of the current orphaned skeleton.
- **[Trade-off] The `validate_version` and `scout-action` blocks are deleted rather than left commented.** → Acceptable: commented code that references a deleted file (`config/version.cue`) is misleading. Deletion forces the next iteration to think through what they actually need rather than uncomment dead code.

## Automated Test Strategy

This change is itself a test infrastructure change. Verification of the change works on two levels:

- **Self-test (the only level that matters for shipping)**: the `test_windows` job on PR #339 (or its replacement PR) goes green. That single check is the success criterion. It exercises every change in this proposal end-to-end: the `COPY` path is correct (build succeeds), the `versiona*` typo is fixed (VS-component test passes), the manifest-driven version test passes (Flutter version read from `config/version.json` matches what `flutter --version` reports), the doctor smoke test passes, the `CMD` is set (the workflow runs Pester and gets a non-zero exit on failure).
- **No new test infrastructure**: Pester is already installed via `script/InstallPester.ps1`; no new tooling is added. The change is a *reduction* in tooling (Go module removed).

There is no unit-test layer below the Pester suite because the assertions are inherently integration-level — they require the real image to run. Local verification by contributors uses `docker compose run --rm windows-test` (which starts to work as part of this change).

## Observability

- **Failure surface**: every assertion is a Pester test. Pester emits per-test pass/fail with file:line in the workflow log. `Invoke-Pester -Configuration @{Output=@{Verbosity='Detailed'}}` (already configured in `script/RunPester.ps1`) shows the failing assertion's expected vs. actual.
- **No silent failures possible**: `RunPester.ps1` ends with `Exit $LASTEXITCODE`, so any Pester test failure propagates to a non-zero `docker run` exit, which fails the workflow step. The `set -e`-equivalent for PowerShell (`$ErrorActionPreference = 'Stop'`) is already configured in the test stage's `SHELL` directive.
- **Build-stage failures** (e.g., a future bad `COPY` path) surface as standard `docker build` errors with the failing instruction in the workflow log. There is no need for additional logging because the failing layer is named in the error.
- **No telemetry sent off-platform**: GitHub Actions logs are the entire observability surface. Maintainers monitor `gh run list --workflow=windows.yml --limit 5` (or the PR check UI).

## Migration Plan

1. Land this change on PR #339 (or replace #339 with a fresh PR built off the current `windows` branch).
2. Force-push the branch after fixing the `COPY` and pattern, and confirm `test_windows` goes from "in_progress forever" to a green check.
3. Delete the Go module files in the same commit as the Dockerfile fix; rerun the workflow to confirm no path now references `test/windows/main*.go`.
4. Squash-merge PR #339 with a non-empty body referencing this proposal.
5. No rollback is needed because every change is additive to the test surface or is a deletion of unused code; if the new Pester tests are wrong, they fail loudly and a follow-up fix applies — there is no production behavior to revert.

## Open Questions

- Should `windows.yml` upload Pester output as a workflow artifact (e.g., NUnit XML) for easier triage? *Tentatively no for this change* — the inline log is sufficient and adds no maintenance. Reopen if maintainers find themselves repeatedly digging through long Detailed-verbosity logs.
- Should there be a smoke test that runs `flutter create` + `flutter build windows` end-to-end in the test stage? *Out of scope here* — the build is already exercised in the `flutter` stage via `flutter create build_app; flutter build windows;` (Dockerfile lines 64, 81). Re-running it inside the `test` stage would multiply build time without new signal. Revisit if a regression slips past the existing build step.
