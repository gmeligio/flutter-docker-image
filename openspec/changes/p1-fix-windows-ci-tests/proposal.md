## Why

PR #339 ("ci: test windows image") has been open for ~12 months and still cannot turn green: `windows.Dockerfile` copies `./test/Windows.Tests.ps1` from a path that no longer exists (the file was moved to `./test/windows/` when the dockertest skeleton was added), and the Pester pattern for the `VC.CMake.Project` package has a typo (`,versiona*`) that would never match a real Visual Studio package directory. As a result the `flutter-windows` image has *zero* automated verification on every PR, while the `flutter-android` image runs `container-structure-test` and Docker Scout. This change is what's needed to actually land PR #339 and start producing a meaningful CI signal for the Windows image.

## What Changes

- Fix `windows.Dockerfile` `COPY` to source `./test/windows/Windows.Tests.ps1` (the real path).
- Fix `test/windows/Windows.Tests.ps1` `BeLikeExactly` pattern: `,versiona*` → `,version=*` to match the pattern actually written by `vs_BuildTools.exe`.
- Add a Flutter version assertion that reads `config/version.json` and asserts `flutter --version` inside the container reports the same `flutter.version`. This converts the test job from "image builds" to "image is the version we shipped."
- Add a `flutter doctor` smoke assertion that fails the test when doctor reports any error (warnings on platform-specific tooling are tolerated).
- Set a default `CMD` in the `test` stage of `windows.Dockerfile` so `docker compose run windows-test` (and equivalent local invocations) actually runs Pester instead of exiting silently. The CI workflow continues to invoke `RunPester.ps1` explicitly.
- Remove the dead `test/windows/main.go`, `test/windows/main_test.go`, `test/windows/go.mod`, `test/windows/go.sum`. The `ory/dockertest` harness was scaffolded in commit `df7666e` but never wired into CI, never builds the image it tries to run, and has its only useful assertion (the Pester `Exec`) commented out. Pester running inside the container is the chosen verification mechanism.
- Either delete or wire up the two commented-out blocks in `.github/workflows/windows.yml`: the `docker/scout-action` step and the `validate_version` job (which still references the deleted `config/version.cue`). This change deletes them because Scout/version-validation parity is out of scope; the follow-up changes (`p2`, `p3`) reintroduce them deliberately.
- Set a non-empty body on PR #339 describing the test surface.

## Capabilities

### New Capabilities

- `windows-image-testing`: defines what `.github/workflows/windows.yml` and `test/windows/Windows.Tests.ps1` are required to verify about the `flutter-windows` Docker image on every pull request — Flutter version match, doctor health, presence of pinned Visual Studio components, and analytics-disabled telemetry config.

### Modified Capabilities

_None._ The Windows image previously had no spec; the existing `flutter-version-update` and `actions-version-tracking` specs are not touched.

## Impact

- Affected files: `windows.Dockerfile`, `test/windows/Windows.Tests.ps1`, `.github/workflows/windows.yml`, `script/RunPester.ps1` (no change expected, but inputs change), `docker-compose.yml` (windows-test service still works).
- Removed files: `test/windows/main.go`, `test/windows/main_test.go`, `test/windows/go.mod`, `test/windows/go.sum`.
- No release/publish behavior changes — `release.yml` is untouched. Distribution of the Windows image is the explicit subject of `p2-release-windows-image`.
- No version manifest changes — `config/schema.cue` is untouched. Tracking VS BuildTools / Win11 SDK / CMake versions in `config/version.json` is the explicit subject of `p3-windows-version-schema`.
- Risk: the only CI signal here is a slow (`windows-2025`, multi-hour) Windows container build. This change does not address build duration; a green check is the success criterion, not a fast green check.
