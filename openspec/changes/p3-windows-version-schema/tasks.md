## 1. Extend the CUE schema

- [x] 1.1 Add `#SemverQuad: { version!: =~ "^\\d+\\.\\d+\\.\\d+\\.\\d+$" }` to `config/schema.cue` alongside the existing `#SemverPatch`.
- [x] 1.2 Add a `#WindowsToolchain` definition with sub-fields `git: #SemverPatch`, `vsBuildTools.cmakeProject: #SemverQuad`, `vsBuildTools.windows11Sdk.build!: int`, `vsBuildTools.vcTools: #SemverQuad`.
- [x] 1.3 Extend `#Version` to require `windows: #WindowsToolchain`.
- [x] 1.4 Run `cue vet config/schema.cue -d '#Version' config/version.json` and confirm it fails (because `version.json` doesn't yet have the `windows` block — the next group fixes this).

## 2. Backfill `config/version.json`

- [ ] 2.1 Read the current values from `windows.Dockerfile`: Git `2.46.0`, Win11SDK build `22621`. Source the four-part component versions from `VisualStudio.vsman` (fetched via `aka.ms/vs/17/release/channel` → `Microsoft.VisualStudio.Manifests.VisualStudio` payload URL; see Decision in design.md). As of 2026-05-21: `Microsoft.VisualStudio.Component.VC.CMake.Project` = `17.14.36510.44`, `Microsoft.VisualStudio.Workload.VCTools` = `17.14.36331.10`. Rerun the query close to merge time so backfilled values match what `windows.yml` will actually install.
- [ ] 2.2 Add the `windows` block to `config/version.json` with those four values.
- [ ] 2.3 Run `cue vet config/schema.cue -d '#Version' config/version.json`; it should now exit 0.

## 3. Remove version literals from `windows.Dockerfile`

- [ ] 3.1 Replace `ARG git_version=2.46.0` with `ARG git_version` (no default).
- [ ] 3.2 Add `ARG vs_cmake_version`, `ARG vs_win11sdk_build`, `ARG vs_vctools_version` (no defaults) before the `vs_BuildTools.exe` invocation.
- [ ] 3.3 Replace the literal `--add Microsoft.VisualStudio.Component.Windows11SDK.22621` with `--add Microsoft.VisualStudio.Component.Windows11SDK.${env:vs_win11sdk_build}` (or the correct PowerShell expansion syntax inside the RUN command).
- [ ] 3.4 The CMake and VCTools `--add` lines do not embed versions in the component id — versions are picked up from the channel and asserted later by Pester. Leave the `--add` lines alone for these.

## 4. Surface the new fields via `setEnvironmentVariables.js`

- [ ] 4.1 Open `script/setEnvironmentVariables.js`. Add reads for `windows.git.version`, `windows.vsBuildTools.cmakeProject.version`, `windows.vsBuildTools.windows11Sdk.build`, `windows.vsBuildTools.vcTools.version`.
- [ ] 4.2 Export each via `core.exportVariable` as `GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, `VS_VCTOOLS_VERSION`.
- [ ] 4.3 Confirm existing exported variables are unchanged.

## 5. Wire build args into the workflows

- [ ] 5.1 In `.github/workflows/windows.yml`, update the `docker build` invocation in the `Test image and push to local Docker daemon` step to pass `--build-arg git_version=${{ env.GIT_VERSION }}`, `--build-arg vs_cmake_version=${{ env.VS_CMAKE_VERSION }}`, `--build-arg vs_win11sdk_build=${{ env.VS_WIN11SDK_BUILD }}`, `--build-arg vs_vctools_version=${{ env.VS_VCTOOLS_VERSION }}`.
- [ ] 5.2 If `p2-release-windows-image` is already merged, apply the same `--build-arg` changes to the `release_windows` job in `.github/workflows/release.yml`.

## 6. Tighten the Pester assertions

- [ ] 6.1 In `test/windows/Windows.Tests.ps1`, add a `BeforeAll` block that reads `config\version.json` via `Get-Content -Raw | ConvertFrom-Json` into `$manifest`.
- [ ] 6.2 Add a Git version test that runs `git --version`, parses the leading three-part semver (`X.Y.Z` from `git version X.Y.Z.windows.N`), and asserts equality with `$manifest.windows.git.version`.
- [ ] 6.3 Tighten the existing CMake assertion: change pattern from `,version=*` to `,version=$($manifest.windows.vsBuildTools.cmakeProject.version)*`.
- [ ] 6.4 Tighten the existing Win11SDK assertion: change to match `Microsoft.VisualStudio.Component.Windows11SDK.$($manifest.windows.vsBuildTools.windows11Sdk.build),version*`.
- [ ] 6.5 Tighten the existing VCTools assertion: change pattern from `,version=*` to `,version=$($manifest.windows.vsBuildTools.vcTools.version)*`.

## 7. Add `update_windows_version` to `update_version.yml`

- [ ] 7.1 Add a job `update_windows_version` after `update_flutter_version`. Set `runs-on: ubuntu-24.04`, `needs: update_flutter_version`, `if: ${{ needs.update_flutter_version.outputs.new_version == 'true' }}`. Note: this job runs in parallel with `update_android_version`.
- [ ] 7.2 Job step: download the `flutter_version.json` artifact (parallel pattern with `update_android_version`).
- [ ] 7.3 Job step: `curl -fsSL https://api.github.com/repos/git-for-windows/git/releases/latest | jq -r '.tag_name'`; strip leading `v` and trailing `.windows.N`; export as `GIT_VERSION_NEW`.
- [ ] 7.4 Job steps to resolve VS component versions (two-step fetch — the channel manifest alone does NOT contain per-component versions; they live in `vsman`):
  - [ ] 7.4a `curl -fsSL https://aka.ms/vs/17/release/channel -o channel.json`
  - [ ] 7.4b Extract the catalog URL and SHA: ``vsman_url=$(jq -r '.channelItems[] | select(.id=="Microsoft.VisualStudio.Manifests.VisualStudio") | .payloads[0].url' channel.json)`` and ``vsman_sha=$(jq -r '.channelItems[] | select(.id=="Microsoft.VisualStudio.Manifests.VisualStudio") | .payloads[0].sha256' channel.json)``
  - [ ] 7.4c `curl -fsSL "$vsman_url" -o vsman.json` (~17 MB)
  - [ ] 7.4d Verify SHA-256: `echo "$vsman_sha  vsman.json" | sha256sum -c -`. Fail the job on mismatch.
  - [ ] 7.4e Extract versions: `jq -r '.packages[] | select(.id=="Microsoft.VisualStudio.Component.VC.CMake.Project") | .version' vsman.json` (and analogously for `Microsoft.VisualStudio.Workload.VCTools`). Document the jq paths in comments so future maintainers can update them if the catalog manifest restructures.
  - [ ] 7.4f Upload both `channel.json` and `vsman.json` as workflow artifacts (90-day retention) for forensic record. This is the mitigation that lets us skip committing the manifest into git (see resolved question in design.md).
- [ ] 7.5 Job step: write the four resolved values into `config/version.json` using `jq` (preserving existing keys).
- [ ] 7.6 Job step: validate with `cue vet config/schema.cue -d '#Version' config/version.json`. Fail the job on non-zero exit.
- [ ] 7.7 Job step: upload `config/version.json` as an artifact named `version.json.windows` (so it doesn't collide with the Android artifact).
- [ ] 7.8 In `update_docs_and_create_pr`, add a `download` step for the new artifact and a merge step that combines the Android-emitted `version.json` and the Windows-emitted `version.json` into one. Document the merge order: Android artifact wins for `flutter`/`android` keys, Windows artifact wins for `windows` keys.

## 8. Validate end-to-end

- [ ] 8.1 Push the branch; the `windows.yml` PR check builds the image with the new build args and runs the tightened Pester suite. Confirm green.
- [ ] 8.2 Run `update_version.yml` via `workflow_dispatch` (which runs unconditionally on the dispatch branch); confirm a draft PR is opened with a non-empty `windows` block diff. (If Flutter is not changing, the dispatch will be a no-op; force a dispatch on a test branch where `flutter_version.json` has been hand-edited.)

## 9. Documentation

- [ ] 9.1 Update `docs/src/windows.mdx` (and the auto-generated `docs/windows.md`) to note that the Windows toolchain versions are pinned in `config/version.json` and refreshed by the monthly upgrade PR.
- [ ] 9.2 Remove now-completed TODO items in `docs/windows.md` referring to "test where is installed" and "snapshot of flutter config" — those are covered by the Pester suite now.

## 10. Archive

- [ ] 10.1 After merge and confirmation that the next scheduled `update_version.yml` produces a sensible Windows-bumping PR, archive this change so the `windows-version-tracking` spec is promoted to `openspec/specs/` and the `flutter-version-update` delta is applied to the existing spec there.
