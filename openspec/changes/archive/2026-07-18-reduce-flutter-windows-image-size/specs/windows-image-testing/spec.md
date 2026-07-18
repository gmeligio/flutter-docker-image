# windows-image-testing (delta)

## ADDED Requirements

### Requirement: The suite asserts a Windows app builds with the installed toolchain

The Pester suite SHALL run `flutter create` followed by `flutter build windows` and assert the build exits 0, proving the installed VS toolchain (the `Workload.VCTools` workload, the Windows SDK, and CMake) is complete and detectable by Flutter's `vswhere` query. This mirrors the android suite (`gradlew bundleRelease`) and web suite (`flutter build web`), which make a real build their primary gate.

The experience context is the maintainer who changes the VS component set: an install that Flutter's `vswhere -requires` check does not accept — even when the packages install and the VS instance reports `isComplete=true` — is caught here as a named test failure ("flutter build windows must succeed"), rather than surfacing only as a cryptic "Unable to find suitable Visual Studio toolchain" at image-build time. This is exactly the class of failure that motivated the test: on the Build Tools SKU, `vswhere -requires Microsoft.VisualStudio.Workload.NativeDesktop` returns no match, so only `Workload.VCTools` yields a detectable toolchain.

#### Scenario: A Windows app builds successfully

- **GIVEN** the image built with the `Workload.VCTools` toolchain
- **WHEN** the Pester build test runs `flutter create` + `flutter build windows`
- **THEN** the build exits 0
- **AND** the test passes

#### Scenario: An undetectable toolchain fails the build test

- **GIVEN** an image whose VS workload/components Flutter's `vswhere -requires` check does not accept (e.g. the `NativeDesktop` workload on the Build Tools SKU, which vswhere reports as NO MATCH)
- **WHEN** the Pester build test runs `flutter build windows`
- **THEN** the build exits non-zero
- **AND** the test fails, naming that the build did not succeed
