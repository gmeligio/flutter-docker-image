## Why

The published `flutter-windows` image is 6.32 GB compressed, and the Visual Studio Build Tools layer alone is 3.43 GB — 54% of the whole image. It installs the broad `Microsoft.VisualStudio.Workload.VCTools` workload, which drags in recommended/optional components beyond what `flutter build windows` needs, and it ships ~99 MB of throwaway build residue plus VS installer logs that a later cleanup layer cannot reclaim. Trimming to the minimal component set and confining residue to its producing layer shrinks the image every consumer pulls, with no change to build speed and no new maintenance surface.

## What Changes

- **Replace the broad VCTools workload with explicit minimal components** in `windows.Dockerfile`: swap `--add Microsoft.VisualStudio.Workload.VCTools` for `--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.${vs_win11sdk_build} --add Microsoft.VisualStudio.Component.VC.CMake.Project`. The CMake and Windows 11 SDK components are already explicit today; only the workload → `VC.Tools.x86.x64` swap is new.
- **Squash the `build_app` ghost layer** (~99 MB): run `flutter build windows` and `Remove-Item -Recurse build_app` in the **same** `RUN` so the build output never commits to a persistent layer. The warm-up build itself is kept — it validates the toolchain at image-build time.
- **Clean VS installer logs in-layer**: remove `%TEMP%\dd_setup_*` inside the same `RUN` as the `vs_buildtools.exe` install, since a later cleanup layer does not shrink the earlier one.
- **Update the version manifest key and its validation** to track the VC tools *component* version (`Microsoft.VisualStudio.Component.VC.Tools.x86.x64`) instead of the workload version, keeping `config/version.json`, `script/setEnvironmentVariables.js`, and the CUE schema consistent with what the Dockerfile now installs.
- **Update the Pester suite** to assert the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` package directory instead of `Microsoft.VisualStudio.Workload.VCTools`.
- Explicitly **out of scope**: multi-stage `COPY --from` of VS (breaks `flutter build windows` — `vswhere` needs a complete VS instance) and deleting Flutter's `.git` (breaks version detection). Both are ruled out with evidence in issue #517.

## Capabilities

### New Capabilities

_None._ This change modifies how existing Windows-image capabilities behave; it introduces no new capability.

### Modified Capabilities

- `windows-image-testing`: the pinned VS-component assertion changes from `Microsoft.VisualStudio.Workload.VCTools` to `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`. The requirement "Tests assert presence of pinned Visual Studio components" and its scenarios must name the component actually installed. The `flutter doctor` health requirement is unchanged (it still must report `[✓] Visual Studio`), but it becomes the primary functional gate proving the trimmed component set is sufficient.
- `windows-version-tracking`: the tracked field `windows.vsBuildTools.vcTools.version` changes meaning from "VCTools **workload** version" to the `VC.Tools.x86.x64` **component** version, and the on-disk validation asserts the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64,version=<x>` directory rather than `Workload.VCTools,version=<x>`. The auto-update reader (`update-version.yml`) that resolves this version from the VS catalog manifest must resolve the component, not the workload.

## Impact

- **`windows.Dockerfile`** (lines 75–93): the `vs_buildtools.exe` install `RUN`, the `flutter build windows` / `Remove-Item build_app` sequence.
- **`test/windows/Windows.Tests.ps1`** (lines 94–97): the VCTools package-directory assertion.
- **`config/version.json`**, **`config/schema.cue`**, **`script/setEnvironmentVariables.js`**: the `vcTools` version key semantics (component vs workload) if the resolved version differs.
- **`.github/workflows/update-version.yml`**: the VS-catalog reader that populates `vcTools.version`.
- **No change** to build-args, workflow structure, runner, base image, or build speed. Size-only.
- **Validation is mandatory and empirical**: the trimmed component set is unverified for Flutter — the broad workload may include a component the build silently needs. The change is only correct if a rebuilt image (a) passes the existing Pester suite, (b) reports `[✓] Visual Studio` from `flutter doctor`, (c) successfully runs `flutter build windows`, and (d) shows a real size reduction in `docker history`.
- Full findings and evidence: gmeligio/flutter-docker-image#517.
