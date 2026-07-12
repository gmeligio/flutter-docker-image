## Why

The published `flutter-windows` image is 6.32 GB compressed, and the Visual Studio Build Tools layer alone is 3.43 GB — 54% of the whole image. It installs the broad `Microsoft.VisualStudio.Workload.VCTools` workload, which drags in recommended/optional components beyond what `flutter build windows` needs, and it ships ~99 MB of throwaway build residue plus VS installer logs that a later cleanup layer cannot reclaim. Trimming to the minimal component set and confining residue to its producing layer shrinks the image every consumer pulls, with no change to build speed and no new maintenance surface.

## What Changes

- **Replace the broad VCTools workload with the NativeDesktop workload plus the explicit MSVC compiler** in `windows.Dockerfile`: swap `--add Microsoft.VisualStudio.Workload.VCTools` for `--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64`. `NativeDesktop` is the C++ desktop toolchain Flutter's `vswhere` query requires; the explicit compiler component is needed because it is only a *Recommended* (not Required) dependency of the workload. This set is narrower than the original `VCTools` (v140/v141 toolsets, Clang, ATL/MFC, ASAN, vcpkg, second SDK). CMake and Windows 11 SDK stay explicit. (Two earlier attempts — bare component, then workload-only — failed `flutter build windows`; see design.md D1.)
- **Squash the `build_app` ghost layer** (~99 MB): run `flutter build windows` and `Remove-Item -Recurse build_app` in the **same** `RUN` so the build output never commits to a persistent layer. The warm-up build itself is kept — it validates the toolchain at image-build time, and on failure it dumps `flutter doctor -v` + installed VS packages + `vswhere` output so a broken component set is diagnosable from the build log.
- **Clean VS installer logs in-layer**: remove `%TEMP%\dd_*` inside the same `RUN` as the `vs_buildtools.exe` install, since a later cleanup layer does not shrink the earlier one.
- **Add a `flutter build windows` capability test** to the Pester suite, mirroring the android (`gradlew bundleRelease`) and web (`flutter build web`) suites that make a real build their primary gate. This turns a broken/incomplete VS toolchain into a named test failure instead of a cryptic image-build error.
- **Make `config/version.json` 1:1 with the VS install**: add a `nativeDesktop` field so every `--add` directive (CMake, Win11SDK, VC.Tools compiler, NativeDesktop workload) has exactly one tracked field, one auto-update reader in `update-version.yml`, and one Pester assertion. Removes the workload-vs-component ambiguity that caused the failures. `vcTools.version` unambiguously tracks the `VC.Tools.x86.x64` compiler.
- Explicitly **out of scope**: multi-stage `COPY --from` of VS (breaks `flutter build windows` — `vswhere` needs a complete VS instance) and deleting Flutter's `.git` (breaks version detection). Both are ruled out with evidence in issue #517.

## Capabilities

### New Capabilities

_None._ This change modifies how existing Windows-image capabilities behave; it introduces no new capability.

### Modified Capabilities

- `windows-image-testing`: the pinned VS-component assertion changes from `Microsoft.VisualStudio.Workload.VCTools` to `Microsoft.VisualStudio.Workload.NativeDesktop`. The requirement "Tests assert presence of pinned Visual Studio components" and its scenarios must name the workload actually installed. The `flutter doctor` health requirement is unchanged (it still must report `[✓] Visual Studio`), and it is the primary functional gate proving the trimmed workload is sufficient — a too-narrow set builds but fails `flutter build windows`.
- `windows-version-tracking`: the tracked field `windows.vsBuildTools.vcTools.version` changes meaning from the `Workload.VCTools` version to the `Workload.NativeDesktop` version, and the on-disk validation asserts the `Microsoft.VisualStudio.Workload.NativeDesktop,version=<x>` directory rather than `Workload.VCTools,version=<x>`. The auto-update reader (`update-version.yml`) that resolves this version from the VS catalog manifest must resolve `Workload.NativeDesktop`.

## Impact

- **`windows.Dockerfile`** (lines 75–93): the `vs_buildtools.exe` install `RUN`, the `flutter build windows` / `Remove-Item build_app` sequence.
- **`test/windows/Windows.Tests.ps1`** (lines 94–97): the VCTools package-directory assertion.
- **`config/version.json`**, **`config/schema.cue`**, **`script/setEnvironmentVariables.js`**: the `vcTools` version key semantics (component vs workload) if the resolved version differs.
- **`.github/workflows/update-version.yml`**: the VS-catalog reader that populates `vcTools.version`.
- **No change** to build-args, workflow structure, runner, base image, or build speed. Size-only.
- **Validation is mandatory and empirical**: the trimmed component set is unverified for Flutter — the broad workload may include a component the build silently needs. The change is only correct if a rebuilt image (a) passes the existing Pester suite, (b) reports `[✓] Visual Studio` from `flutter doctor`, (c) successfully runs `flutter build windows`, and (d) shows a real size reduction in `docker history`.
- Full findings and evidence: gmeligio/flutter-docker-image#517.
