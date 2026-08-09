Ordered by the migration plan in `design.md`: each group is independently
revertable, and each group after 1 switches exactly one build leg.

Shape amended during implementation: a composite action, not a reusable workflow.
See design D1 — a `workflow_call` workflow is a separate job, and every Linux leg
depends on job-local state (`ci.yml`'s `load: true` local daemon, `build.yml`'s
fork handoff) that cannot cross a job boundary.

## 1. The shared action and emitter hardening (design D1, D2, D3)

- [x] 1.1 Capture a per-leg baseline from a recent CI run: the resolved `docker buildx build` command line for `build.yml` push path, `build.yml` fork path, `ci.yml`, and `release.yml` — seven build-args each, plus target, cache and output flags
- [ ] 1.2 Add `.github/actions/build-linux-image/action.yml` as a composite action modelled on `.github/actions/clean-runner-disk`, wrapping `docker/build-push-action` with `file: android.Dockerfile`
- [ ] 1.3 Declare the seven `build-args` lines **once** inside it, reproducing current names and values exactly (`flutter_version`, `fastlane_version`, `android_java_version`, `android_build_tools_version`, `android_platform_versions`, `android_ndk_version`, `cmake_version`) — note this is seven, not six; `android_java_version` was wired by PR #537
- [ ] 1.4 Declare inputs for what the legs legitimately differ in: `target`, `tags`, `labels`, `cache-from`, `cache-to`, `push`, `load`, `outputs`, `sbom`, `provenance` — cache values pass through verbatim, since the four legs use three different shapes (design D2)
- [ ] 1.5 Expose the build's `imageid`/`digest` as action outputs so a caller can consume them as it does from the inline step today (`build.yml` `id: build`)
- [ ] 1.6 Omit every Windows value — the action must never name `git_version`, `vs_cmake_version`, `vs_win11sdk_build`, or `vs_vctools_version`, so the `GIT_VERSION` collision cannot arise (design D1)
- [ ] 1.7 Fail `script/setEnvironmentVariables.js` with a named error if a manifest path does not resolve, rather than exporting `undefined` (design D3)
- [ ] 1.8 Log the resolved manifest-derived values so the job log shows what was passed (design D3)
- [ ] 1.9 Leave all four callers untouched in this group — nothing uses the new action yet, so it is inert

## 2. Switch `ci.yml` (design D1 migration step 2)

- [ ] 2.1 Replace the build step at `ci.yml:74-91` with a `uses:` of the action, passing `target: android`, `load: true`, `cache-from: type=gha`, `cache-to: type=gha,mode=max`, and the metadata tags/labels
- [ ] 2.2 Verify the resolved command line matches the 1.1 `ci.yml` baseline — same seven names, same values, same target, same cache flags
- [ ] 2.3 Confirm the `Test image` step still resolves its image from `steps.metadata` and that `container-structure-test` passes `test/android.yml`

## 3. Switch `build.yml` (design D1 migration step 3)

- [ ] 3.1 Replace the push step (`build.yml:142-165`) with a `uses:`, passing `push: true`, `sbom: true`, `provenance: mode=max`, and the registry cache refs — keeping `id: build` and the `is_fork != 'true'` condition on the caller's step
- [ ] 3.2 Replace the fork step (`build.yml:171-188`) with a `uses:`, passing `outputs: type=docker` and `cache-from` only, keeping the `is_fork == 'true'` condition
- [ ] 3.3 Confirm the fork handoff still works unchanged — `steps.handoff`, the re-tag at `:195-201`, `docker save`, and the artifact upload all stay in the same job and need no edit
- [ ] 3.4 Verify both legs' build-args against the 1.1 baseline (push path from a run; fork path against source, per `baseline.md`)

## 4. Switch `release.yml` (design D1 migration step 3)

- [ ] 4.1 Replace `release.yml:100-121` with a `uses:`, passing `push: true` and the per-image scoped gha cache (`type=gha,scope=${{ matrix.name }}`) — preserve current behaviour; do not unify the `buildkitd-flags: --debug` drift here (design open question 1)
- [ ] 4.2 Verify the build-args against the seven in `baseline.md` — the latest release run predates PR #537, so verify against source rather than that run

## 5. Verification

- [ ] 5.1 Confirm no workflow file still contains an inline `build-args:` block naming `flutter_version` or `android_ndk_version` for `android.Dockerfile`
- [ ] 5.2 Confirm a warm-cache rebuild whose only manifest change is `fastlane.version` still serves the Flutter clone layer from cache (per-ARG granularity preserved, design D2)
- [ ] 5.3 Confirm the Windows leg is untouched — `windows-image.yml` still assembles its own PowerShell argument array and still reads `GIT_VERSION`/`VS_*` from the emitter
- [ ] 5.4 Confirm `prepare-release.yml`, `update-version.yml`, and `release.yml:198` still get the emitter exports they read (`FLUTTER_VERSION`, `IMAGE_REPOSITORY_PATH`)
- [ ] 5.5 Lint the changed workflows and the new action (`mise run lint` or the repo's actionlint equivalent) before opening the PR

## 6. Wrap-up

- [ ] 6.1 Open the PR with a Conventional Commit title, one logical concern
- [ ] 6.2 Note in the PR that no build-argument name or value changed, that each leg was diffed against its pre-refactor baseline, and that the shape changed from a reusable workflow to a composite action during implementation (design D1)
