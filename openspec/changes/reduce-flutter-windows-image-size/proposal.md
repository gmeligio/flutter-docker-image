## Why

The published `flutter-windows` image is 6.32 GB compressed. The Visual Studio Build Tools layer (3.43 GB, 54%) looked like the biggest reduction target — the theory was to replace the broad `Workload.VCTools` with a narrower component set. **That theory was disproven under CI investigation** (PR #518): Flutter's toolchain detection runs `vswhere -requires <workload> VC.Tools.x86.x64 VC.CMake.Project`, accepting either the `NativeDesktop` or `VCTools` workload — but on the Build Tools SKU **only `Workload.VCTools` registers as satisfied** (`NativeDesktop` returns NO MATCH from vswhere even when its packages install and `isComplete=true`). Since VCTools is the very workload the trim aimed to remove, no VS-layer reduction is achievable without breaking `flutter build windows`.

What remains genuinely worth doing, and is independent of the (impossible) trim: reclaim the ~99 MB of throwaway `build_app` residue that ships because it is deleted in a later layer, clean VS installer logs in-layer, and — the durable win — add the toolchain-completeness test coverage that was missing (the Windows suite only parsed `flutter doctor`, so the toolchain breakage above surfaced as a cryptic build error instead of a named test failure).

## What Changes

- **Keep `Workload.VCTools`** in `windows.Dockerfile` (the only workload Flutter's vswhere detects on Build Tools), documenting the NativeDesktop-NO-MATCH finding inline so the trim is not re-attempted. No component change ships — this is the proven-working install.
- **Add a `vs_buildtools.exe` exit-code check**: capture the installer's exit code (treating 3010/reboot as success) and fail the build on any other non-zero, so a partial VS install fails loudly instead of shipping silently.
- **Squash the `build_app` ghost layer** (~99 MB): run `flutter build windows` and `Remove-Item -Recurse build_app` in the **same** `RUN` so the build output never commits to a persistent layer. The warm-up build is kept — it validates the toolchain at image-build time.
- **Clean VS installer logs in-layer**: remove `%TEMP%\dd_*` inside the same `RUN` as the install.
- **Add a `flutter build windows` capability test** to the Pester suite, mirroring the android (`gradlew bundleRelease`) and web (`flutter build web`) suites that make a real build their primary gate. This turns a broken/incomplete VS toolchain into a named test failure instead of a cryptic image-build error — the coverage gap that let the toolchain breakage go undiagnosed.
- **Add on-failure diagnostics** to the warm-up build: dump `flutter doctor -v`, Flutter's exact per-ID `vswhere -requires` result, the install's `isComplete`/`isLaunchable` flags, and the MSVC toolset dirs — permanent debuggability for any future toolchain regression.
- Explicitly **out of scope / proven dead**: the VS component trim (VCTools is the only detectable workload on Build Tools — no size win possible); multi-stage `COPY --from` of VS (breaks vswhere detection); deleting Flutter's `.git` (breaks version detection). All ruled out with evidence in issue #517 and this change's design.md.

## Capabilities

### New Capabilities

_None._ This change modifies how existing Windows-image capabilities behave; it introduces no new capability.

### Modified Capabilities

- `windows-image-testing`: adds a new requirement — the Pester suite SHALL run `flutter build windows` and assert it succeeds (mirroring the android/web build gates). The existing VS-component assertions and `Workload.VCTools` pin are unchanged (the trim was reverted). The build test is the primary functional gate: it proves the toolchain can actually compile a Windows app, catching detection breakage that the on-disk package assertions and `flutter doctor` parse alone missed.
- `windows-version-tracking`: unchanged — `windows.vsBuildTools.vcTools.version` continues to track the `Workload.VCTools` version, asserted against the `Microsoft.VisualStudio.Workload.VCTools,version=<x>` directory. (The proposed 4/5-field manifest was reverted along with the trim.)

## Impact

- **`windows.Dockerfile`** (lines 75–93): the `vs_buildtools.exe` install `RUN`, the `flutter build windows` / `Remove-Item build_app` sequence.
- **`test/windows/Windows.Tests.ps1`** (lines 94–97): the VCTools package-directory assertion.
- **`config/version.json`**, **`config/schema.cue`**, **`script/setEnvironmentVariables.js`**: the `vcTools` version key semantics (component vs workload) if the resolved version differs.
- **`.github/workflows/update-version.yml`**: the VS-catalog reader that populates `vcTools.version`.
- **No change** to build-args, workflow structure, runner, base image, or build speed. Size-only.
- **Validation is mandatory and empirical**: the trimmed component set is unverified for Flutter — the broad workload may include a component the build silently needs. The change is only correct if a rebuilt image (a) passes the existing Pester suite, (b) reports `[✓] Visual Studio` from `flutter doctor`, (c) successfully runs `flutter build windows`, and (d) shows a real size reduction in `docker history`.
- Full findings and evidence: gmeligio/flutter-docker-image#517.
