# windows-image-testing (delta)

## MODIFIED Requirements

### Requirement: Tests assert presence of pinned Visual Studio components

The Pester suite SHALL assert that the directories at `$env:ProgramData\Microsoft\VisualStudio\Packages\` contain entries matching the components installed by `windows.Dockerfile`: `Microsoft.VisualStudio.Component.VC.CMake.Project`, `Microsoft.VisualStudio.Component.Windows11SDK.22621`, and `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`. The match pattern SHALL accept any installed `version=...` suffix.

The experience context is detecting silent removal or rename of a VS component in the Dockerfile — the package directory is the on-disk evidence that the component installed. After the workload-to-component trim, the C++ toolchain is provided by the explicit `VC.Tools.x86.x64` component rather than the `Workload.VCTools` workload, so the on-disk evidence the suite checks for is the component directory.

#### Scenario: All three components match

- **GIVEN** the image was built from the current `windows.Dockerfile`
- **WHEN** the VS-component Pester tests run
- **THEN** each of `VC.CMake.Project`, `Windows11SDK.22621`, and `VC.Tools.x86.x64` matches `*,version=*`
- **AND** all three tests pass

#### Scenario: Pattern correctly accepts the on-disk format

- **GIVEN** a real package directory `Microsoft.VisualStudio.Component.VC.CMake.Project,version=17.13.35919.96`
- **WHEN** the `BeLikeExactly` assertion runs against pattern `Microsoft.VisualStudio.Component.VC.CMake.Project,version=*`
- **THEN** the assertion passes

### Requirement: Doctor test detects a missing required VS component

The Pester `flutter doctor` assertion SHALL fail when a Visual Studio component required for Windows desktop builds is absent, so that removing the C++ toolchain from `windows.Dockerfile` is caught as a test failure rather than shipping a non-functional image.

The experience context is a maintainer who accidentally deletes or mistypes the C++ toolchain component: `flutter doctor` is the functional gate that proves the trimmed component set is still sufficient to build Windows apps, independent of the on-disk package-directory assertions.

#### Scenario: Removing the C++ toolchain component fails the doctor test

- **GIVEN** a PR that removes the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` line from `windows.Dockerfile`
- **AND** the image still builds (the component removal does not break the build itself)
- **WHEN** the `flutter doctor` Pester test runs
- **THEN** `flutter doctor` reports `[✗] Visual Studio` (or an equivalent missing/partial-toolchain marker)
- **AND** the doctor test fails

#### Scenario: Trimmed component set reports a healthy toolchain

- **GIVEN** the image built with the explicit components `VC.Tools.x86.x64`, `Windows11SDK.22621`, and `VC.CMake.Project` (no `Workload.VCTools`)
- **WHEN** the `flutter doctor` Pester test runs
- **THEN** `flutter doctor` reports `[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps`
- **AND** the doctor test passes
