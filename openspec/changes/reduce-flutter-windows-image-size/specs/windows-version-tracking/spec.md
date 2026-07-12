# windows-version-tracking (delta)

## MODIFIED Requirements

### Requirement: Pester suite asserts exact toolchain versions

The Pester suite at `test/windows/Windows.Tests.ps1` SHALL read `config/version.json` (already copied into the test stage by `p1-fix-windows-ci-tests`) and assert that:

- `git --version` reports a version equal to `windows.git.version`,
- the `Microsoft.VisualStudio.Component.VC.CMake.Project,version=<x>` directory's `<x>` equals `windows.vsBuildTools.cmakeProject.version`,
- the `Microsoft.VisualStudio.Component.Windows11SDK.<build>` directory's `<build>` equals `windows.vsBuildTools.windows11Sdk.build`,
- the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64,version=<x>` directory's `<x>` equals `windows.vsBuildTools.vcTools.version`.

The `windows.vsBuildTools.vcTools.version` field tracks the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` **component** version (the explicit C++ toolchain component installed by `windows.Dockerfile`), not a workload version.

The experience context is the reviewer of an upgrade PR: any drift between the manifest the PR proposes and the image actually produced is caught as a hard test failure, not silent semantics drift.

#### Scenario: Manifest and image agree on every Windows version

- **GIVEN** the test image was built with the build args derived from the current `config/version.json`
- **WHEN** the Pester suite runs
- **THEN** all four version assertions pass

#### Scenario: Manifest claims a version the image does not have

- **GIVEN** a PR that bumps `windows.git.version` to a version different from the build arg actually passed to the image
- **WHEN** the Pester suite runs
- **THEN** the Git version test fails with a message naming both the manifest value and the in-image value

### Requirement: Monthly upgrade PR includes Windows toolchain updates

The `update-version.yml` workflow SHALL include a job (`update-windows-version`) that attempts to update the `windows` block in `config/version.json` whenever it runs. The job SHALL:

- read the latest Git for Windows release from `https://api.github.com/repos/git-for-windows/git/releases/latest` and write the resolved version to `windows.git.version`,
- read VS BuildTools component versions from Microsoft's VS catalog manifest (`VisualStudio.vsman`) reached via the channel manifest at `https://aka.ms/vs/17/release/channel`, resolving `windows.vsBuildTools.vcTools.version` from the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` package (not `Microsoft.VisualStudio.Workload.VCTools`), consistent with the component the Dockerfile installs,
- verify upstream consistency by comparing `channel.json.info.productSemanticVersion` against `vsman.json.info.productSemanticVersion`; on equality, write the extracted versions and emit a CUE-validated fragment artifact containing only the `windows` block,
- on inequality (Microsoft's release pipeline is mid-publish or otherwise inconsistent), skip the version write, emit a `windows_skipped=true` job output, and exit successfully without uploading a fragment artifact.

The job SHALL upload the raw `channel.json` and `vsman.json` it fetched as a `vs-manifests` workflow artifact on every run (regardless of skip vs. success), so the bytes that drove the decision are preserved for retroactive inspection.

The composed `version.json` consumed by `update-docs-and-create-pr` SHALL be produced by the dedicated `compose-version-manifest` job, not by `update-docs-and-create-pr` itself. When `update-windows-version` did not produce a fragment, `compose-version-manifest` SHALL carry forward the `windows` block from the base branch unchanged.

The experience context is the maintainer reviewing the monthly upgrade PR. They expect (a) Android and Windows toolchain bumps to appear in the same PR when both upstream sources are healthy, (b) the PR to still open with whichever platforms updated when others' upstreams are transiently inconsistent, (c) the PR body to make any skipped platform visible without having to dig through workflow logs, and (d) composition and validation to happen in dedicated jobs before any PR work begins.

#### Scenario: Monthly run produces a Windows-aware upgrade PR

- **GIVEN** a scheduled `update-version.yml` run where both Git for Windows and the VS catalog manifest are reachable and internally consistent
- **WHEN** `update-windows-version` runs
- **THEN** it resolves `windows.vsBuildTools.vcTools.version` from the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` package
- **AND** emits a CUE-validated `windows` fragment that the composed manifest includes in the upgrade PR

#### Scenario: VC tools version resolves from the component, not the workload

- **GIVEN** a fetched `vsman.json` containing both a `Microsoft.VisualStudio.Workload.VCTools` package and a `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` package with differing versions
- **WHEN** `update-windows-version` extracts the VC tools version
- **THEN** it selects the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` version
- **AND** writes it to `windows.vsBuildTools.vcTools.version`
