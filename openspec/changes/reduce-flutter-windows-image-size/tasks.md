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

- [ ] 5.1 **(CI-only — requires Windows daemon; runs on `windows-2025` via the `Windows` workflow on PR)** Build the `test` target locally or in CI and run the Pester suite; confirm all version assertions and the VS-component assertions pass.
- [ ] 5.2 **(CI-only)** Confirm `flutter doctor` reports `[✓] Windows Version` and `[✓] Visual Studio - develop Windows apps` (the functional sufficiency gate). If it reports `[!]`/`[✗]`, `--add` the specific missing component and rebuild — do NOT revert to `Workload.VCTools`.
- [ ] 5.3 **(CI-only)** Confirm the `flutter` stage's warm-up `flutter build windows` succeeds (a failing build fails `docker build` and blocks publish).
- [ ] 5.4 **(CI/manual — needs a built image)** Run `docker history` (or compare GHCR manifest layer sizes) before and after; record the measured size reduction in the PR description.
- [x] 5.5 Run `cue vet config/schema.cue -d '#Version' config/version.json` to confirm the manifest still validates.

## 6. Close out

- [ ] 6.1 Reference issue #517 in the PR; note the measured before/after size and that build speed is unchanged.

## 7. Correction — CI-driven pivot from bare component to NativeDesktop workload

The first CI run (PR #518) built the image but failed `flutter build windows` with "Unable to find suitable Visual Studio toolchain": the bare `VC.Tools.x86.x64` component is not what Flutter's `vswhere` query recognizes. Corrected to the `NativeDesktop` workload (Flutter's documented requirement, still far narrower than the original `VCTools` workload's 20 dependencies).

- [x] 7.1 Change `windows.Dockerfile` `--add` from `Component.VC.Tools.x86.x64` to `Microsoft.VisualStudio.Workload.NativeDesktop` (no `--includeRecommended`).
- [x] 7.2 Update `update-version.yml` jq selector, `config/version.json` (`vcTools.version` → `17.14.36517.7`, the NativeDesktop version), and the Pester assertion to track `Workload.NativeDesktop`.
- [x] 7.3 Re-run `cue vet` (passes) and update proposal/design/specs to reflect NativeDesktop.
- [x] 7.4 Second CI iteration: `Workload.NativeDesktop` alone (no `--includeRecommended`) ALSO failed — the MSVC compiler `VC.Tools.x86.x64` is a *Recommended*, not Required, dep of NativeDesktop, so the workload shell installed without the compiler. Final fix: `--add Workload.NativeDesktop --add VC.Tools.x86.x64` (workload gives the desktop toolchain `vswhere` needs; explicit component guarantees the compiler). Manifest tracks the `VC.Tools.x86.x64` component version (`17.14.36510.44`).
- [ ] 7.5 Re-verify on Windows CI (supersedes 5.1-5.4): Pester passes, `flutter doctor [✓] Visual Studio`, warm-up `flutter build windows` succeeds, and `docker history` shows a size reduction vs the pre-change image.
