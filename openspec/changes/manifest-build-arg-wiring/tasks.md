Ordered by the migration plan in `design.md`: each group is independently
revertable, and each group after 1 switches exactly one build leg.

## 1. The reusable workflow and emitter hardening (design D1, D2, D3)

- [x] 1.1 Capture a per-leg baseline from a recent CI run: the resolved `docker buildx build` command line for `build.yml` push path, `build.yml` fork path, `ci.yml`, and `release.yml` — seven build-args each, plus target, cache and output flags
- [ ] 1.2 Add `.github/workflows/linux-image.yml` as a `workflow_call` workflow modelled on `windows-image.yml:7-27`, owning: manifest read, `clean-runner-disk`, buildx setup, registry logins, `metadata-action`, and `docker/build-push-action` with `file: android.Dockerfile`
- [ ] 1.3 Declare the seven `build-args` lines **once** inside it, reproducing current names and values exactly (`flutter_version`, `fastlane_version`, `android_java_version`, `android_build_tools_version`, `android_platform_versions`, `android_ndk_version`, `cmake_version`) — note this is seven, not six; `android_java_version` was wired by PR #537
- [ ] 1.4 Declare typed inputs for the five dimensions the legs legitimately differ in: `target`, `push`, `cache-backend` (`registry`|`gha`), `attestations`, `registries` (design D2)
- [ ] 1.5 Declare `workflow_call` outputs carrying what `build.yml:59-62` exposes to `test-image`/`scan-image`, keyed so a matrix build does not collapse them to the last successful run (design D2 risk)
- [ ] 1.6 Omit every Windows value — the workflow must never name `git_version`, `vs_cmake_version`, `vs_win11sdk_build`, or `vs_vctools_version`, so the `GIT_VERSION` collision cannot arise (design D1)
- [ ] 1.7 Fail `script/setEnvironmentVariables.js` with a named error if a manifest path does not resolve, rather than exporting `undefined` (design D3)
- [ ] 1.8 Log the resolved manifest-derived values so the job log shows what was passed (design D3)
- [ ] 1.9 Leave all four callers untouched in this group — nothing calls the new workflow yet, so it is inert

## 2. Switch `ci.yml` (design D1 migration step 2)

- [ ] 2.1 Replace `ci.yml:74-91` with a call to `linux-image.yml` passing `cache-backend: gha`, no attestations, no GHCR login, load-only output
- [ ] 2.2 Verify the resolved command line matches the 1.1 `ci.yml` baseline — same seven names, same values, same target, same cache flags
- [ ] 2.3 Confirm `container-structure-test` still passes `test/android.yml` on the resulting image

## 3. Switch `build.yml` (design D1 migration step 3)

- [ ] 3.1 Replace the push path (`build.yml:142-165`) with a call passing `push: true`, `attestations: true`, `cache-backend: registry`
- [ ] 3.2 Replace the fork path (`build.yml:171-188`) with a call passing `push: false` and local-artifact output, preserving the `is_fork` condition
- [ ] 3.3 Rewire `test-image` and `scan-image` to the reusable workflow's outputs, confirming the matrix does not collapse them (task 1.5)
- [ ] 3.4 Verify both legs' command lines against their 1.1 baselines

## 4. Switch `release.yml` (design D1 migration step 3)

- [ ] 4.1 Replace `release.yml:100-121` with a call, preserving the Quay login (`release.yml:93`) and `buildkitd-flags: --debug` (`release.yml:78`) via inputs — preserve current behaviour; do not unify drift here (design open question 1)
- [ ] 4.2 Verify the command line against the 1.1 `release.yml` baseline

## 5. Verification

- [ ] 5.1 Confirm no workflow file still contains an inline `build-args:` block naming `flutter_version` or `android_ndk_version` for `android.Dockerfile`
- [ ] 5.2 Confirm a warm-cache rebuild whose only manifest change is `fastlane.version` still serves the Flutter clone layer from cache (per-ARG granularity preserved, design D2)
- [ ] 5.3 Confirm the Windows leg is untouched — `windows-image.yml` still assembles its own PowerShell argument array and still reads `GIT_VERSION`/`VS_*` from the emitter
- [ ] 5.4 Confirm `prepare-release.yml`, `update-version.yml`, and `release.yml:198` still get the emitter exports they read (`FLUTTER_VERSION`, `IMAGE_REPOSITORY_PATH`)

## 6. Wrap-up

- [ ] 6.1 Open the PR with a Conventional Commit title, one logical concern
- [ ] 6.2 Note in the PR that no build-argument name or value changed, and that each leg's resolved command line was diffed against its pre-refactor baseline
