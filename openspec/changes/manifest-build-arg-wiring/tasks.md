Ordered by the migration plan in `design.md`: each group is independently
revertable, and only group 2 changes what a build receives.

## 1. Table-driven emitter (design D1, D2)

- [ ] 1.1 Capture the current `--build-arg` set as a baseline from a recent CI run's `docker buildx build` command line — six args with their values — to diff against after the refactor
- [ ] 1.2 Add the mapping table to `script/setEnvironmentVariables.js`: one row per manifest path → build-argument name, reproducing all current names exactly (`android.ndk.version` → `android_ndk_version`, `android.cmake.version` → `cmake_version`, `windows.git.version` → `git_version`, `windows.vsBuildTools.cmakeProject.version` → `vs_cmake_version`, `windows.vsBuildTools.windows11Sdk.build` → `vs_win11sdk_build`, `windows.vsBuildTools.vcTools.version` → `vs_vctools_version`)
- [ ] 1.3 Give `android.platforms` a declared transform in the same table (array of `{version}` → space-joined string), so the one non-scalar shape is visible rather than special-cased in code
- [ ] 1.4 Emit `BUILD_ARGS` as newline-separated `name=value` pairs via `core.exportVariable`, restricted to the Linux build's six manifest-derived arguments
- [ ] 1.5 Fail the emitter with a named error if a table row references a manifest path that does not resolve, rather than exporting an empty value
- [ ] 1.6 Log the resolved `BUILD_ARGS` so the job log shows what was passed once the call sites stop listing arguments (design D1 legibility mitigation)
- [ ] 1.7 Keep every existing per-name export in place for now — this group is inert and nothing reads `BUILD_ARGS` yet

## 2. Collapse the four call sites (design D2)

- [ ] 2.1 Replace the build-args block with `build-args: ${{ env.BUILD_ARGS }}` in `build.yml` push path (~:158-164), `build.yml` fork path (~:180-186), `ci.yml` (~:84-90), `release.yml` (~:112-118)
- [ ] 2.2 Verify the emitted `--build-arg` set is byte-identical to the 1.1 baseline — same six names, same values, same count, no behaviour change
- [ ] 2.3 Confirm no workflow file still contains an inline `flutter_version=` or `android_ndk_version=` build-arg line

## 3. Retire the superseded exports (design D3)

- [ ] 3.1 Grep the workflows for each per-name export (`FASTLANE_VERSION`, `ANDROID_BUILD_TOOLS_VERSION`, `ANDROID_PLATFORM_VERSIONS`, `ANDROID_NDK_VERSION`, `CMAKE_VERSION`) and confirm the build step was its only reader
- [ ] 3.2 Delete the exports that group 2 made redundant
- [ ] 3.3 Keep `FLUTTER_VERSION` (read by tagging and test steps) and `IMAGE_REPOSITORY_PATH` (not manifest-derived) — confirm by grep that both still have readers

## 4. Verification

- [ ] 4.1 `container-structure-test` passes `test/android.yml` against an image built through the new path
- [ ] 4.2 Confirm a warm-cache rebuild whose only manifest change is `fastlane.version` still serves the Flutter clone layer from cache (per-ARG granularity preserved, design D2)
- [ ] 4.3 Confirm the Windows leg is untouched — `windows-image.yml` still assembles its own PowerShell argument array

## 5. Wrap-up

- [ ] 5.1 Open the PR with a Conventional Commit title, one logical concern
- [ ] 5.2 Note in the PR that no build-argument name or value changed, and that the resolved command line was diffed against the pre-refactor baseline
