# windows-image-testing (delta)

## ADDED Requirements

### Requirement: The suite asserts a Windows app builds with the installed toolchain

The Pester suite SHALL run `flutter create` followed by `flutter build windows` and assert the build exits 0, proving the installed VS toolchain (the NativeDesktop workload, the `VC.Tools.x86.x64` MSVC compiler, the Windows SDK, and CMake) is complete and detectable by Flutter. This mirrors the android suite (`gradlew bundleRelease`) and web suite (`flutter build web`), which make a real build their primary gate.

The experience context is the maintainer who trims or changes the VS component set: an incomplete toolchain that still lets the image build but cannot compile a Windows app is caught here as a named test failure ("flutter build windows must succeed"), rather than surfacing only as a cryptic "Unable to find suitable Visual Studio toolchain" at image-build time.

#### Scenario: A Windows app builds successfully

- **GIVEN** the image built with the pinned VS toolchain
- **WHEN** the Pester build test runs `flutter create` + `flutter build windows`
- **THEN** the build exits 0
- **AND** the test passes

#### Scenario: An incomplete toolchain fails the build test

- **GIVEN** an image whose VS component set omits a piece Flutter's Windows build requires (e.g. the MSVC compiler or the Windows SDK)
- **WHEN** the Pester build test runs `flutter build windows`
- **THEN** the build exits non-zero
- **AND** the test fails, naming that the build did not succeed

## MODIFIED Requirements

### Requirement: Tests assert presence of pinned Visual Studio components

The Pester suite SHALL assert that the directories at `$env:ProgramData\Microsoft\VisualStudio\Packages\` contain entries matching every VS `--add` directive in `windows.Dockerfile`: `Microsoft.VisualStudio.Component.VC.CMake.Project`, `Microsoft.VisualStudio.Component.Windows11SDK.22621`, `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, and `Microsoft.VisualStudio.Workload.NativeDesktop`. The match pattern SHALL accept any installed `version=...` suffix. Each asserted package corresponds 1:1 to a field in `config/version.json` `windows.vsBuildTools` (`cmakeProject`, `windows11Sdk`, `vcTools`, `nativeDesktop`).

The experience context is detecting silent removal or rename of a VS component in the Dockerfile — the package directory is the on-disk evidence that the component installed. After the workload trim, the C++ desktop toolchain is provided by `Workload.NativeDesktop` plus an explicit `--add` of the `VC.Tools.x86.x64` compiler (Flutter's required toolchain, materially narrower than the former `Workload.VCTools`), so the on-disk evidence the suite asserts is the `VC.Tools.x86.x64` compiler directory.

#### Scenario: All four packages match

- **GIVEN** the image was built from the current `windows.Dockerfile`
- **WHEN** the VS-component Pester tests run
- **THEN** each of `VC.CMake.Project`, `Windows11SDK.22621`, `VC.Tools.x86.x64`, and `Workload.NativeDesktop` matches `*,version=*`
- **AND** all four tests pass

#### Scenario: Pattern correctly accepts the on-disk format

- **GIVEN** a real package directory `Microsoft.VisualStudio.Component.VC.CMake.Project,version=17.13.35919.96`
- **WHEN** the `BeLikeExactly` assertion runs against pattern `Microsoft.VisualStudio.Component.VC.CMake.Project,version=*`
- **THEN** the assertion passes

### Requirement: Doctor test detects a missing required VS component

The Pester `flutter doctor` assertion SHALL fail when the Visual Studio C++ desktop toolchain required for Windows desktop builds is absent, so that removing the toolchain from `windows.Dockerfile` is caught as a test failure rather than shipping a non-functional image.

The experience context is a maintainer who accidentally deletes or narrows the C++ desktop workload below what Flutter needs: `flutter doctor` is the functional gate that proves the installed set is still sufficient to build Windows apps, independent of the on-disk package-directory assertions. This gate is load-bearing — a too-narrow component set (e.g. the bare `VC.Tools.x86.x64` component without the NativeDesktop toolchain) builds the image but fails `flutter build windows` with "Unable to find suitable Visual Studio toolchain".

#### Scenario: Removing the C++ desktop workload fails the doctor test

- **GIVEN** a PR that removes the `Microsoft.VisualStudio.Workload.NativeDesktop` line from `windows.Dockerfile`
- **AND** the image still builds (the workload removal does not break the image build itself)
- **WHEN** the `flutter doctor` Pester test runs
- **THEN** `flutter doctor` reports `[✗] Visual Studio` (or an equivalent missing/partial-toolchain marker)
- **AND** the doctor test fails

#### Scenario: Trimmed workload reports a healthy toolchain

- **GIVEN** the image built with `Workload.NativeDesktop` plus the explicit `Windows11SDK.22621` and `VC.CMake.Project` components (no `Workload.VCTools`)
- **WHEN** the `flutter doctor` Pester test runs
- **THEN** `flutter doctor` reports `[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps`
- **AND** the doctor test passes
