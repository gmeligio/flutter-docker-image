## Why

`config/version.json` is the single source of truth for Android tooling versions (`buildTools`, `cmake`, `ndk`, `gradle`, `cmdlineTools`, `platforms`) and Flutter itself, and `config/schema.cue` validates it. The Windows build, by contrast, has hardcoded version-bearing strings scattered across `windows.Dockerfile` (Git for Windows `2.46.0`, `Microsoft.VisualStudio.Component.VC.CMake.Project`, `Microsoft.VisualStudio.Component.Windows11SDK.22621`, `Microsoft.VisualStudio.Workload.VCTools`) with no manifest entry, no CUE constraint, and no Renovate-driven update path. After `p1-fix-windows-ci-tests` lands, the Pester suite asserts these components are *present*, but cannot assert they are at any particular version because there is no source of truth to compare against. This change extends `config/schema.cue` and `config/version.json` with a `windows` block, plumbs the values into `windows.Dockerfile` build args, and adds a corresponding `update_windows_version` job to `update_version.yml` so monthly upgrade PRs cover the Windows toolchain alongside Flutter and Android.

## What Changes

- Add a `#WindowsToolchain` definition to `config/schema.cue` and constrain `#Version` to include a top-level `windows: #WindowsToolchain` field. Initial fields:
  - `git: #SemverPatch` (Git for Windows version, currently hardcoded as `2.46.0`),
  - `vsBuildTools.cmakeProject: #SemverPatch` (the four-part version VS reports as `version=A.B.C.D`; we model it as a `#SemverQuad` introduced alongside),
  - `vsBuildTools.windows11Sdk: { build!: int }` (the `22621` from `Windows11SDK.22621` — already a numeric build id),
  - `vsBuildTools.vcTools: #SemverQuad` (workload version reported by VS).
- Add `#SemverQuad: { version!: =~ "^\\d+\\.\\d+\\.\\d+\\.\\d+$" }` to `schema.cue` (VS components publish four-part versions; the existing `#SemverPatch` rejects them).
- Populate the new `windows` block in `config/version.json` with the values currently hardcoded in `windows.Dockerfile`. This is a one-time backfill; the values do not change.
- In `windows.Dockerfile`, replace the hardcoded `git_version=2.46.0` ARG default with no default (force the build arg), and add `vs_cmake_version`, `vs_win11sdk_build`, `vs_vctools_version` build args. The `--add Microsoft.VisualStudio.Component.Windows11SDK.<build>` argument is composed from the build arg.
- In `script/setEnvironmentVariables.js`, surface the new fields as env vars (`GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, `VS_VCTOOLS_VERSION`) so `windows.yml` and `release.yml` (post-`p2`) can pass them to the build.
- In `windows.yml` and (after `p2`) `release.yml`'s `release_windows`, pass these env vars as `--build-arg` values to `docker build`.
- In the Pester suite (added by `p1`), tighten the VS component assertions from `*,version=*` to `*,version=<exact-version>*`, and assert Git's reported `git --version` matches `windows.git.version`.
- Add a new `update_windows_version` job to `update_version.yml`, parallel to `update_android_version` (both gated by `update_flutter_version`'s `result == 'true'` output). The job:
  - reads upstream Git for Windows latest release from `https://api.github.com/repos/git-for-windows/git/releases/latest`,
  - reads VS BuildTools component versions from the VS catalog manifest `VisualStudio.vsman` (fetched via `aka.ms/vs/17/release/channel` → `Microsoft.VisualStudio.Manifests.VisualStudio` payload, SHA-256-verified; see design for two-step fetch),
  - writes the new fields into `config/version.json` and uploads the artifact for the `validate_config_version` and `update_docs_and_create_pr` jobs to consume.
- The Windows-relevant fields fall under the existing `flutter-version-update` PR cadence — same upgrade PR carries both Android and Windows updates.

## Capabilities

### New Capabilities

- `windows-version-tracking`: defines what `config/version.json`, `config/schema.cue`, and `update_version.yml` must guarantee about Windows toolchain versions — that they live in the manifest, are CUE-validated, are passed into the Dockerfile build, are asserted by the Pester suite at the manifest's pinned values, and are refreshed monthly by the upgrade PR.

### Modified Capabilities

- `flutter-version-update`: the requirement "Upgrade PR contains a coherent, validated `version.json`" is extended so the PR's `version.json` also passes `cue vet` against the new `windows` block. The existing scenario that asserts Android `buildTools.version` matches Flutter's `packages.txt` is unchanged; a new scenario asserts Git for Windows tracks the latest GitHub-released Git for Windows tag.
- `windows-image-testing` (introduced by `p1`): the VS component requirements are tightened from `*,version=*` to exact-version match against `config/version.json`'s `windows` block; a new requirement asserts Git's reported version matches the manifest.

## Impact

- Affected files: `config/schema.cue`, `config/version.json`, `config/flutter_version.json` (unchanged — this is `#Version` not `#FlutterVersion`), `windows.Dockerfile`, `script/setEnvironmentVariables.js`, `.github/workflows/windows.yml`, `.github/workflows/update_version.yml`, `.github/workflows/release.yml` (after `p2` lands), `test/windows/Windows.Tests.ps1`.
- Cross-cutting: this is the largest of the three changes. Touches schema, manifest, dockerfile, two workflows, the version-update node script, and the test suite.
- Depends on: `p1-fix-windows-ci-tests` landed (Pester tests exist to tighten); `p2-release-windows-image` ideally landed (so the build args also flow through release).
- Does not depend on the Renovate-via-`gx` integration (`actions-version-tracking`) since Windows toolchain versions are tracked in `config/version.json` like Android, not in `gx.toml`. Renovate is unaffected.
- Risk: VS BuildTools component versioning is provided by Microsoft via the VS catalog manifest (`vsman`, ~17 MB, referenced and SHA-pinned by the channel manifest); the source of truth and the update API have less stability than Flutter's `releases_linux.json`. Mitigation in design.
- Risk: tightening Pester assertions to exact versions means a Microsoft-side patch bump to a VS component will fail CI even though the image still works. Mitigation: track at the build-id level for Win11SDK (already coarse), at the publisher's `version=` for the others, accept that an upgrade PR is required when Microsoft ships a patch.
