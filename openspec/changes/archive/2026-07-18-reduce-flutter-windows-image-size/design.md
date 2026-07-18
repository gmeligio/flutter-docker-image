## OUTCOME (resolved on PR #518)

**The VS component trim (D1/D2 below) is impossible and was reverted.** Per-ID `vswhere` diagnostics proved Flutter's toolchain detection (`vswhere -requires <workload> VC.Tools VC.CMake`) accepts `NativeDesktop` or `VCTools`, but on the Build Tools SKU only `Workload.VCTools` registers as satisfied — `NativeDesktop` returns NO MATCH even with `isComplete=true` and the compiler on disk. VCTools is the "broad" workload the trim aimed to remove, so no VS-layer reduction is achievable. **What shipped:** the `flutter build windows` Pester test, the `build_app` squash (~99 MB, D3), the `%TEMP%` cleanup (D4), the `vs_buildtools.exe` exit-code check, and permanent on-failure diagnostics. D1/D2 below are retained as the record of what was tried and why it failed. D3/D4/D5 shipped.

## Context

The published `flutter-windows` image is 6.32 GB compressed (GHCR manifest, v3.44.6). Layer breakdown: VS BuildTools install **3431 MB (54%)**, servercore base 1523 MB + OS update 607 MB (fixed), Flutter clone+precache 616 MB, and a `build_app` residue layer of **99 MB** that is deleted in a later layer but still ships. The VS install (`windows.Dockerfile:75-81`) uses the broad `Microsoft.VisualStudio.Workload.VCTools` workload, which pulls recommended/optional components beyond the C++ toolchain `flutter build windows` requires.

Two alternatives were investigated and rejected with evidence (issue #517): multi-stage `COPY --from` of VS breaks `flutter build windows` because `vswhere` requires a complete VS instance (setup-instance metadata + HKLM state a file copy drops); deleting Flutter's `.git` breaks version/channel detection (the shell wrapper hard-gates on `.git`). This change pursues only the safe, in-place levers.

## Goals / Non-Goals

**Goals:**
- Reduce the VS BuildTools layer by installing the minimal explicit component set instead of the broad workload.
- Reclaim the ~99 MB `build_app` ghost layer by confining the build output to its producing `RUN`.
- Remove VS installer logs in the same layer they are produced.
- Keep `config/version.json`, its CUE schema, `setEnvironmentVariables.js`, `update-version.yml`, and the Pester suite mutually consistent with the component actually installed.

**Non-Goals:**
- Build-speed reduction (this is size-only; the VS install still runs every build).
- Multi-stage `COPY --from` of VS (breaks the build — out of scope).
- Deleting or compacting Flutter's `.git` (breaks version detection — out of scope).
- Changing the runner (`windows-2025`), base image, or build-args.

## Decisions

**D1 — Install the NativeDesktop workload plus the explicit MSVC compiler component.** Replace `--add Microsoft.VisualStudio.Workload.VCTools` with `--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64`. The Windows 11 SDK and CMake components stay explicit. **This took two CI iterations on PR #518 to get right:**
1. *Bare `VC.Tools.x86.x64` component alone* — failed `flutter build windows` with "Unable to find suitable Visual Studio toolchain". Flutter's `vswhere` query needs a recognized C++ *desktop* toolchain (the `NativeDesktop.Core` component group), which the raw compiler component doesn't register.
2. *`Workload.NativeDesktop` alone, no `--includeRecommended`* — same failure. The MSVC compiler (`VC.Tools.x86.x64`) is a **Recommended**, not Required, dependency of NativeDesktop, so without `--includeRecommended` the workload shell installed but the compiler did not.
3. *`Workload.NativeDesktop` + explicit `VC.Tools.x86.x64`* — the workload supplies the desktop toolchain `vswhere` looks for; the explicit `--add` guarantees the compiler lands. This is the minimal working set, and still far narrower than the original `Workload.VCTools` (20 deps: v140/v141 toolsets, Clang, ATL/MFC, ASAN, vcpkg, second SDK) and narrower than `NativeDesktop --includeRecommended` (Graphics, IntelliCode, Copilot, vcpkg, test adapters, etc.).

**D2 — The `vcTools.version` manifest field tracks the MSVC compiler component.** `config/version.json`'s `windows.vsBuildTools.vcTools.version` keeps its key and CUE shape (`#SemverQuad`); its meaning is the `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` version (the compiler — the load-bearing toolchain piece, and the on-disk package dir the Pester suite can assert). Three consumers move in lockstep: `update-version.yml` (jq selector resolves `Component.VC.Tools.x86.x64`), the Pester assertion (`Windows.Tests.ps1:96`), and the Dockerfile. The build-arg name `vs_vctools_version` / env `VS_VCTOOLS_VERSION` is unchanged to avoid churn in the workflow plumbing.

**D3 — Squash `build_app` into one `RUN`.** Move `flutter build windows` and `Remove-Item -Recurse build_app` into a single `RUN` (they are currently `windows.Dockerfile:85` and `:93`, split by `WORKDIR` changes and the entrypoint `COPY`). The warm-up build is retained — it is the image-build-time toolchain validation gate — but its output never commits to a persistent layer. The intervening `COPY docker_entrypoint.ps1` and `ENTRYPOINT` must be reordered so they don't sit between build and cleanup.

**D4 — Clean VS logs in the install `RUN`.** Add `Remove-Item $env:TEMP\dd_setup_* -Force -ErrorAction SilentlyContinue` (and any bootstrapper temp) to the end of the existing `vs_buildtools.exe` `RUN` (`:75-81`), which already deletes `vs_BuildTools.exe`.

**D5 — Validation is the acceptance gate, not an afterthought.** Because the trimmed set is unverified for Flutter, the change is accepted only if the rebuilt image passes the Pester suite, `flutter doctor` reports `[✓] Visual Studio`, `flutter build windows` succeeds, and `docker history` shows a real size reduction. This gate already did its job: the first attempt (bare `VC.Tools.x86.x64` component) built the image but failed `flutter build windows` with "Unable to find suitable Visual Studio toolchain" in CI on PR #518, which drove the correction to `Workload.NativeDesktop`. If a future narrowing fails the same way, the fix is to add back the specific missing component/workload rather than silently widening back to `Workload.VCTools`.

## Automated Test Strategy

- **Existing Pester suite is the primary net.** `test/windows/Windows.Tests.ps1` already gates on (a) `flutter doctor` reporting `[✓] Windows Version` and `[✓] Visual Studio` — the functional proof the toolchain is complete — and (b) the presence of the pinned VS-component package directories. Updating the VCTools assertion (line 96) to `Microsoft.VisualStudio.Workload.NativeDesktop` keeps the on-disk check honest; the `flutter doctor` check is what actually proves sufficiency of the trimmed set.
- **Critical path:** the change is only correct if `flutter build windows` produces a working Windows binary. The `flutter doctor` assertion is a proxy; the definitive check is an actual `flutter build windows` in the CI path (already exercised at image-build time by the retained warm-up build in the `flutter` stage). If the warm-up build fails, the image build fails — a broken component set cannot be published.
- **CUE validation:** `config/schema.cue` (`#WindowsToolchain.vsBuildTools.vcTools: #SemverQuad`) still validates the field shape; no schema change is needed since only the field's *meaning* changes, not its type. `ci.yml`'s `validate-version-files` job runs `cue vet` and must stay green.
- **Generated-config check:** `build.yml`'s `validate-generated-config` runs `script/update_test.sh` and diffs; if any generated test references the workload string, it must be regenerated.
- **No new test infrastructure** is required — the change rides the existing Pester + doctor + CUE gates.

## Observability

- **Image-build-time failure is loud and blocking:** an insufficient component set surfaces as either a failed `flutter build windows` in the `flutter` stage (fails the `docker build`, so nothing publishes) or a `flutter doctor` `[!]`/`[✗]` caught by the Pester suite in the `test` stage (fails the PR check). There is no silent-failure path to a published-but-broken image.
- **Size regression is measurable:** `docker history <image>` and the GHCR manifest layer sizes make the before/after delta explicit; the PR description should record the measured reduction so a future change that re-bloats the VS layer is visible in review.
- **Version-drift is self-reporting:** the Pester version assertions name both the manifest value and the in-image value on failure, so a mismatch between `vcTools.version` and the installed `VC.Tools.x86.x64` directory is a named, actionable failure rather than a silent skip.
- **Upstream-resolution changes are auditable:** `update-version.yml` already uploads the raw `channel.json`/`vsman.json` as the `vs-manifests` artifact every run, so the bytes behind any future `vcTools.version` resolution remain inspectable after the selector change.

## Risks / Trade-offs

- **The trimmed set may omit a component Flutter needs (primary risk).** MSBuild for Windows desktop sometimes pulls spectre-mitigated libs or additional SDK pieces the workload included implicitly. Mitigation: the retained warm-up `flutter build windows` and the doctor check catch this at build/test time; the fix is additive (`--add` the specific component), never a revert to the full workload.
- **Three consumers must change together (D2).** If the Dockerfile installs `VC.Tools.x86.x64` but `update-version.yml` still resolves the workload version (or the Pester test still asserts the workload dir), the next auto-update PR or the test will fail. Mitigation: tasks.md sequences all three edits and the validation gate covers the combination.
- **Measured saving is unknown until built.** No published number exists for the workload→component delta on a Flutter image; the win could be smaller than the raw 3.43 GB layer suggests (the C++ toolset itself is load-bearing). Trade-off accepted: even a partial reduction is a net win at zero maintenance cost, and the two residue freebies (D3/D4) are strictly positive regardless.
- **`build_app` squash reorders Dockerfile instructions (D3).** Moving the `ENTRYPOINT`/`COPY` relative to the build/cleanup could subtly change the final image's entrypoint layer. Mitigation: verify the published image's entrypoint still resolves to `docker_entrypoint.ps1` and the `test` stage's Pester entrypoint is unaffected (the `test` stage overrides `ENTRYPOINT`/`CMD` already).
