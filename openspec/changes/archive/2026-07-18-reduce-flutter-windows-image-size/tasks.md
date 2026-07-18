## 1. Trim VS components in the Dockerfile

- [x] 1.1 In `windows.Dockerfile` (the `vs_buildtools.exe` install `RUN`, ~lines 75-81), replace `--add Microsoft.VisualStudio.Workload.VCTools` with `--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64`. Leave the existing `--add Microsoft.VisualStudio.Component.VC.CMake.Project` and `--add Microsoft.VisualStudio.Component.Windows11SDK.${vs_win11sdk_build}` lines unchanged.
- [x] 1.2 Append `%TEMP%` log cleanup to the same install `RUN` (after `Remove-Item vs_BuildTools.exe`): `Remove-Item "$env:TEMP\dd_setup_*" -Force -ErrorAction SilentlyContinue` (and any bootstrapper temp), so VS install logs do not persist in the layer.

## 2. Squash the build_app residue layer

- [x] 2.1 In `windows.Dockerfile`, combine `flutter build windows` (~line 85) and `Remove-Item -Recurse build_app` (~line 93) into a single `RUN` under `WORKDIR "$USERPROFILE/build_app"`, so the ~99 MB build output never commits to a persistent layer. Keep the warm-up build itself.
- [x] 2.2 Reorder the intervening `WORKDIR "$USERPROFILE"`, `COPY ./script/docker_windows_entrypoint.ps1`, and `ENTRYPOINT` so they no longer sit between the build and its cleanup; verify the `flutter` stage's final `ENTRYPOINT` still resolves to `docker_entrypoint.ps1`.

## 3. Keep the version manifest and its consumers consistent

- [x] 3.1 In `.github/workflows/update-version.yml` (~line 172), change the jq selector from `select(.id=="Microsoft.VisualStudio.Workload.VCTools")` to `select(.id=="Microsoft.VisualStudio.Component.VC.Tools.x86.x64")` so `vcTools.version` resolves from the component the Dockerfile installs.
- [x] 3.2 Confirm `config/version.json`'s `windows.vsBuildTools.vcTools.version` value matches the `VC.Tools.x86.x64` component version for the current VS release (the component and workload versions may differ); update the value if needed.
- [x] 3.3 Confirm `config/schema.cue` still validates (`vcTools: #SemverQuad` — no shape change) and that `script/setEnvironmentVariables.js` still exports `VS_VCTOOLS_VERSION` from the same key (no rename).

## 4. Update the Pester assertion

- [x] 4.1 In `test/windows/Windows.Tests.ps1` (~lines 94-97), change the VCTools assertion to match `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` instead of `Microsoft.VisualStudio.Workload.VCTools`, keeping the `,version=$expectedVersion*` pattern and reading from `windows.vsBuildTools.vcTools.version`.
- [x] 4.2 If `script/update_test.sh` generates any test file that embeds the workload string, regenerate it so `build.yml`'s `validate-generated-config` diff stays clean.

## 5. Build, validate, measure

- [x] 5.1 **(CI-only — requires Windows daemon; runs on `windows-2025` via the `Windows` workflow on PR)** Build the `test` target locally or in CI and run the Pester suite; confirm all version assertions and the VS-component assertions pass.
- [x] 5.2 **(CI-only)** Confirm `flutter doctor` reports `[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps` (the functional sufficiency gate). If it reports `[!]`/`[✗]`, `--add` the specific missing component and rebuild — do NOT revert to `Workload.VCTools`.
- [x] 5.3 **(CI-only)** Confirm the `flutter` stage's warm-up `flutter build windows` succeeds (a failing build fails `docker build` and blocks publish).
- [x] 5.4 **(MOOT — no size reduction to measure)** The size trim (VS components) and the `build_app` squash were both proven impossible (see §10, §11), so there is no before/after delta to record. The PR ships as maintenance+UX, documented in the PR description.
- [x] 5.5 Run `cue vet config/schema.cue -d '#Version' config/version.json` to confirm the manifest still validates.

## 6. Close out

- [x] 6.1 Reference issue #517 in the PR; note the measured before/after size and that build speed is unchanged.

## 7. Correction — CI-driven pivot from bare component to NativeDesktop workload

The first CI run (PR #518) built the image but failed `flutter build windows` with "Unable to find suitable Visual Studio toolchain": the bare `VC.Tools.x86.x64` component is not what Flutter's `vswhere` query recognizes. Corrected to the `NativeDesktop` workload (Flutter's documented requirement, still far narrower than the original `VCTools` workload's 20 dependencies).

- [x] 7.1 Change `windows.Dockerfile` `--add` from `Component.VC.Tools.x86.x64` to `Microsoft.VisualStudio.Workload.NativeDesktop` (no `--includeRecommended`).
- [x] 7.2 Update `update-version.yml` jq selector, `config/version.json` (`vcTools.version` → `17.14.36517.7`, the NativeDesktop version), and the Pester assertion to track `Workload.NativeDesktop`.
- [x] 7.3 Re-run `cue vet` (passes) and update proposal/design/specs to reflect NativeDesktop.
- [x] 7.4 Second CI iteration: `Workload.NativeDesktop` alone (no `--includeRecommended`) ALSO failed — the MSVC compiler `VC.Tools.x86.x64` is a *Recommended*, not Required, dep of NativeDesktop, so the workload shell installed without the compiler. Final fix: `--add Workload.NativeDesktop --add VC.Tools.x86.x64` (workload gives the desktop toolchain `vswhere` needs; explicit component guarantees the compiler). Manifest tracks the `VC.Tools.x86.x64` component version (`17.14.36510.44`).
- [x] 7.5 Re-verify on Windows CI (supersedes 5.1-5.4): Pester passes, `flutter doctor [✓] Visual Studio`, warm-up `flutter build windows` succeeds, and `docker history` shows a size reduction vs the pre-change image.

## 8. Add toolchain-completeness coverage (the 3 failures slipped past because tests never built)

The android (`gradlew bundleRelease`) and web (`flutter build web`) suites make a real build their primary gate; the Windows suite only parses `flutter doctor`. Add the missing build gate and make version.json 1:1 with the install so the workload-vs-component ambiguity can't recur.

- [x] 8.1 Add a `Describe "Flutter Windows build"` block to `test/windows/Windows.Tests.ps1` that runs `flutter create` + `flutter build windows` and asserts exit 0 — mirroring web.yml's `flutter build web` gate. This is the assertion that turns a broken VS toolchain into a named test failure instead of a cryptic image-build error.
- [x] 8.2 Add a `nativeDesktop: {version}` field to `config/version.json` `windows.vsBuildTools` and the CUE schema, so every VS `--add` directive has exactly one tracked field (cmakeProject → CMake, windows11Sdk → Win11SDK, vcTools → VC.Tools.x86.x64 compiler, nativeDesktop → Workload.NativeDesktop).
- [x] 8.3 Add the `nativeDesktop` reader to `update-version.yml` (resolve `Workload.NativeDesktop` version) and a Pester dir-assertion for `Microsoft.VisualStudio.Workload.NativeDesktop,version=<x>`, mirroring the existing three component assertions.
- [x] 8.4 Update `setEnvironmentVariables.js` only if `nativeDesktop` needs a build-arg (it does not — VS versions are test-assertions, not install-pins; document this so the field's purpose is clear).
- [x] 8.5 Update proposal/design/specs to reflect the build-capability test and the 4-field version.json, and re-validate CUE + openspec.
- [x] 8.6 Add on-failure diagnostics to the `flutter` stage warm-up build (`flutter doctor -v` + installed VS packages + `vswhere -all`) so a broken component set is diagnosable from the `docker build` log directly — the warm-up fails before the `test` stage runs, so the Pester build test alone cannot surface it. Permanent (helps any future toolchain regression), not throwaway.

## 9. Add Windows 10 SDK — the actual missing component (from doctor diagnostics)

The 4th CI run's on-failure `flutter doctor -v` dump named the real gap: Flutter 3.44.6 needs a **Windows 10 SDK** (the "MSVC v142" line is generic boilerplate — it accepts the latest MSVC, v143 is fine; CMake and Win11SDK installed but doctor still fails without Win10 SDK). The original `Workload.VCTools` bundled `Windows10SDK.19041`; the trim dropped it.

- [x] 9.1 Add `--add Microsoft.VisualStudio.Component.Windows10SDK.${vs_win10sdk_build}` to `windows.Dockerfile` + `ARG vs_win10sdk_build`.
- [x] 9.2 Add `windows10Sdk: {build: 19041}` to `config/version.json` + CUE schema; wire the `vs_win10sdk_build` build-arg through `setEnvironmentVariables.js` (VS_WIN10SDK_BUILD) and `windows-image.yml`.
- [x] 9.3 Carry `windows10Sdk.build` forward in `update-version.yml` (human-pinned like Win11SDK); add the Pester Windows10SDK assertion. Now 5 --add ↔ 5 version.json fields ↔ 5 assertions.
- [x] 9.4 Re-verify on Windows CI: `flutter build windows` succeeds, and MEASURE `docker history` size vs the pre-change image to confirm the trim is actually smaller (the open question — the set is NativeDesktop+v143+Win10SDK+Win11SDK+CMake vs the original VCTools' v140+v141+v142+SDKs).

## 10. Root cause resolved — VS workload trim is IMPOSSIBLE; revert it, keep the wins

Per-ID vswhere diagnostics (PR #518) named the exact failure: `vswhere -requires Microsoft.VisualStudio.Workload.NativeDesktop` returns **NO MATCH** on the Build Tools SKU, even though the workload's packages install and `isComplete=true`. Flutter's `_requiredWorkloads` accepts NativeDesktop OR VCTools; only **VCTools registers** on Build Tools. Since VCTools is the "broad" workload the trim aimed to remove, **no VS-layer size reduction is possible** — the narrow workload Flutter can't detect, the detectable workload is the broad one. Premise disproven.

- [x] 10.1 Revert `windows.Dockerfile` VS install to `--add Workload.VCTools` (+ explicit CMake/Win11SDK pins), documenting the NativeDesktop-NO-MATCH finding inline.
- [x] 10.2 Revert `config/version.json` (drop nativeDesktop + windows10Sdk fields; vcTools tracks the VCTools workload), CUE schema, `setEnvironmentVariables.js` (drop VS_WIN10SDK_BUILD), `windows-image.yml` build-arg, `update-version.yml` reader, and the Pester VCTools assertion.
- [x] 10.3 KEEP the toolchain-independent wins: `flutter build windows` Pester test (the gate that caught all this), build_app squash (~99 MB), %TEMP% cleanup, vs_buildtools exit-code check, and the on-failure doctor+vswhere diagnostics (permanent debuggability).
- [x] 10.4 Verify on Windows CI: build passes on VCTools (proven-working), and confirm the ~99 MB build_app squash actually reduces image size via docker history / GHCR manifest.

## 11. GREEN — landed as maintenance+UX (no size win)

PR #518 fully green (run 29647184831): all 12 checks pass; the `flutter build windows` Pester test executed and passed (64.72s, Tests Passed: 8). Final chain of nested fixes: VCTools toolchain → separate-RUN build_app delete (in-layer squash impossible, file-handle lock) → ASCII em-dash in the Pester test (broke PS parser). Net: NO image-size reduction (both size levers proven impossible), ships a build-capability test + installer exit-code check + lean diagnostics + preserved build-cache warm-up.
