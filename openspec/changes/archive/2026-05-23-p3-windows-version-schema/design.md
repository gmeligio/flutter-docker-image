## Context

The repository already has a strong "manifest is source of truth" discipline for Linux/Android: `config/version.json` declares versions, `config/schema.cue` validates them, `setEnvironmentVariables.js` exports them, `update_version.yml` refreshes them, and `flutter-version-update` is the spec that ties it together. The Windows side has none of this — `windows.Dockerfile` carries hardcoded `git_version=2.46.0`, hardcoded `Windows11SDK.22621`, and no version metadata for the CMake or VCTools components beyond their *names*. After `p1` lands, the Pester suite asserts presence; this change extends to asserting *exact versions*, so the manifest becomes the single point of truth for "which Windows toolchain produced this image."

Constraints:

- Microsoft does not publish a clean, programmatic, monotonic API for VS BuildTools component versions. The closest source is a two-step fetch: the channel manifest at `https://aka.ms/vs/17/release/channel` (JSON, ~90 KB) lists 13 product-level entries all stamped with the overall release version (e.g., `17.14.37314.3`) and references the catalog manifest `VisualStudio.vsman` (JSON, ~17 MB, SHA-256 pinned by the channel) via the `Microsoft.VisualStudio.Manifests.VisualStudio` channel item. `vsman.packages[]` is where per-component versions live (verified 2026-05-21: `VC.CMake.Project` → `17.14.36510.44`, `Windows11SDK.22621` → `17.14.36510.44`, `Workload.VCTools` → `17.14.36331.10`). The channel manifest alone is insufficient.
- The Windows 11 SDK build number (`22621`) is essentially a Microsoft branding choice; it changes infrequently (Win11 22H2, 23H2 etc.) and is not strictly tied to VS BuildTools versions.
- Git for Windows publishes clean GitHub releases at `git-for-windows/git`, but the tag naming is `vM.m.p.windows.N` — the `.windows.N` suffix needs to be stripped before storing as a clean semver.
- `cue` already vendors well in this repo; adding `#SemverQuad` is a one-line addition.
- `setEnvironmentVariables.js` is the chokepoint — every workflow consumes it. Adding fields there ripples to every downstream job for free.

## Goals / Non-Goals

**Goals:**

- `config/version.json` carries every version that the Windows image embeds.
- `windows.Dockerfile` has no version literals — every version is a build arg.
- The Pester suite asserts exact versions, not "any version is fine."
- The monthly upgrade PR carries Windows updates alongside Flutter and Android.
- A maintainer reading `git log -p config/version.json` sees Windows toolchain changes at the same fidelity as Android toolchain changes.

**Non-Goals:**

- Auto-detecting the latest VS BuildTools component versions from Microsoft. The channel manifest is too unstable to drive blind; this change reads it but pins the parsed output, gated behind a manual review step (see decisions).
- Tracking the Microsoft Windows Server Core base image (`mcr.microsoft.com/windows/servercore:ltsc2022@sha256:…`) under the manifest. That digest is already SHA-pinned in the Dockerfile FROM line; Renovate's Docker manager handles it. The `windows` block in `version.json` covers tools installed *on top of* the base, not the base itself.
- Running the Windows update job on `windows-2025`. The job that *fetches* the new versions is a Linux job (it just reads URLs and edits JSON). The image is rebuilt by `windows.yml` and `release.yml` on `windows-2025`.
- Renaming Android-side fields for consistency. `android.buildTools.version` and `windows.vsBuildTools.cmakeProject.version` look asymmetric but match each ecosystem's idioms.

## Decisions

### Decision: VS BuildTools component versions are pinned in `config/version.json`, refreshed from the VS catalog manifest (`vsman`) via a two-step fetch

The `update_windows_version` job (1) fetches `https://aka.ms/vs/17/release/channel`, (2) extracts the `Microsoft.VisualStudio.Manifests.VisualStudio` payload URL + SHA-256, (3) downloads that `VisualStudio.vsman` (~17 MB), (4) verifies the SHA, (5) `jq`s `.packages[] | select(.id == <component>) | .version` for each tracked component, and writes the resolved versions into `config/version.json`. The catalog occasionally drops or renames components, so this is treated as a *suggestion* not a *truth*: the PR is opened with the new values, but the Pester suite then verifies that those values actually install. If they don't, the PR fails and a human pins by hand.

The SHA-pinning of `vsman` by the channel is a free integrity property — the job can trust the catalog without committing it. Also note: `Microsoft.VisualStudio.Component.Windows11SDK.22621` carries the build id (`22621`) in the component **id**, not the version field; the `version` is the VS release stamp. This matches the design's decision to model the SDK build as a bare `int` separate from the `#SemverQuad` version fields.

Alternatives considered:

- **Pin the four versions in the schema (in `schema.cue`) and require a human edit to bump.** Rejected: same review burden, but no automation. The channel-manifest read is cheap and 99% of the time correct.
- **Use Renovate's `vsBuildTools` datasource.** Rejected: no such datasource exists. Adding one is out of scope.

### Decision: Schema additions are `#SemverPatch` (Git), `#SemverQuad` (CMake/VCTools), `int` (Win11SDK build)

Git for Windows publishes three-part versions (e.g., `2.46.0`); `#SemverPatch` matches.

VS components publish four-part versions (e.g., `17.13.35919.96`); a new `#SemverQuad: { version!: =~ "^\\d+\\.\\d+\\.\\d+\\.\\d+$" }` is added to `schema.cue`.

Win11 SDK is identified by a build id, not a semver; modeled as a bare integer. This matches Microsoft's documentation conventions.

### Decision: Build args have no defaults

`windows.Dockerfile` ARG declarations remove all default values. This makes the build fail loudly if a workflow forgets to pass a build arg. The alternative (keep defaults as a fallback) was rejected because a default value is a second source of truth that drifts from `version.json`.

### Decision: Pester reads `config/version.json` once at the top of `Describe`, not in every test

A `BeforeAll` block parses the manifest into PowerShell variables. This keeps each test focused on the assertion, not the parsing. PowerShell's `ConvertFrom-Json` returns nested PSObjects; `$manifest.windows.git.version` is the access pattern.

### Decision: `update_windows_version` runs in parallel with `update_android_version`

Both `needs: update_flutter_version` and gate on `result == 'true'`. They emit separate artifacts that `update_docs_and_create_pr` merges. This mirrors the parallelism decision in `p2-release-windows-image`.

Alternative considered:

- **Sequence Windows after Android.** Rejected: no shared state. The Android job needs `flutter_version.json` (downloaded from the artifact), and the Windows job needs the same — the dependency is on the Flutter job, not on each other.

### Decision: Stripping `.windows.N` suffix from Git for Windows tags

Tag `v2.46.0.windows.1` → store `2.46.0`. The `.windows.1` revision number changes when Git for Windows publishes a fix without a Git upstream change; the underlying Git binary is identical from Flutter's perspective. Storing the upstream Git version aligns with what users see when they run `git --version` (which reports `git version 2.46.0.windows.1` — but the test parses `2.46.0` from the leading three parts).

This means the test compares the leading three parts of `git --version` output to `windows.git.version`. The trailing `.windows.N` is informational, not asserted.

## Risks / Trade-offs

- **[Risk] The VS channel manifest changes structure and the update job starts producing nonsense versions.** → Mitigation: `cue vet` rejects values that don't match `#SemverQuad`. The PR fails its own validation. A human manually pins the right values until the channel-manifest reader is fixed.
- **[Risk] Microsoft yanks a VS component version (it has happened) and the image cannot be rebuilt for a tag that pinned the yanked version.** → Mitigation: the existing tag's image is already pushed and immutable. Future tags use new versions. Old-tag rebuilds (`workflow_dispatch` per `p2`) might fail until the manifest is updated; document this as a known limitation.
- **[Risk] Tightening Pester to exact versions makes the test brittle.** → Acceptable: that's the point. Drift detection is a feature.
- **[Trade-off] More fields in `version.json` mean more review surface for upgrade PRs.** → Acceptable: the alternative is hidden state in the Dockerfile, which has no review surface at all.
- **[Trade-off] `update_windows_version` adds a runtime dependency on `aka.ms/vs/17/release/channel`, `download.visualstudio.microsoft.com` (for `vsman`), and `api.github.com/repos/git-for-windows/git`.** → Acceptable: the workflow already depends on `storage.googleapis.com/flutter_infra_release` and `raw.githubusercontent.com/flutter/flutter`. Three more upstreams is incremental.
- **[Trade-off] `update_windows_version` downloads ~17 MB (`VisualStudio.vsman`) per run.** → Acceptable. `update_version.yml` is scheduled `0 0 * * MON-FRI`, but `update_windows_version` is gated on `update_flutter_version.outputs.new_version == 'true'` (same gating pattern as `update_android_version`), so the fetch only fires when Flutter actually bumped — empirically about once a month. On quiet weekdays the job is skipped and nothing is downloaded. No cross-run caching: the catalog would have to be invalidated against the channel anyway, and at ~once-a-month firing the savings don't justify the cache plumbing.
- **[Forensic mitigation] The job uploads the raw `VisualStudio.vsman` (and the channel JSON) as workflow artifacts.** → 90-day retention is enough to diagnose any "why did this PR pick these versions" question without committing the manifest into git. Avoids the noisy-history tradeoff while preserving the forensic record.

## Automated Test Strategy

- **Schema validation (existing path):** `validate_version_files` job in `build.yml` and `validate_config_version` job in `update_version.yml` already run `cue vet`. Once the `windows` block is required by `#Version`, any `version.json` missing the block fails these jobs. No new test infrastructure.
- **Unit-level test for `setEnvironmentVariables.js`:** none added. The script is small and has no test today; this change preserves the status quo. A regression in env-var emission would surface as a build-arg-not-set failure in `windows.yml` (the build fails loudly because no defaults are kept).
- **Integration test (the load-bearing layer):** the Pester suite running on `windows-2025`. After this change, the suite reads `config/version.json` and asserts toolchain versions match. A CUE-valid manifest that doesn't match the actually-installed image fails the test.
- **End-to-end (monthly):** `update_version.yml` runs on schedule; the PR it opens carries the new `windows` block; `windows.yml` runs against that PR; the Pester suite gates the merge. If Microsoft changed something incompatibly, the PR fails CI and a maintainer intervenes.
- **No new test files** — the Pester suite is extended, not duplicated. The schema test surface is the existing `cue vet` step.

## Observability

- **CUE failures**: `cue vet` prints field-level errors with paths like `windows.vsBuildTools.cmakeProject.version: invalid value …`. The workflow log is the surface.
- **Pester version-mismatch failures**: the test failure message names both the manifest value and the in-image value (e.g., `Expected git --version to report 2.46.0; got 2.45.2`). This is how a maintainer diagnoses why a PR is red.
- **Update-job failures**: if `update_windows_version` cannot reach the VS channel manifest or the GitHub API, the step fails with a 4xx/5xx in the curl/jq pipeline. The job logs the URL it tried.
- **No silent partial updates**: `update_docs_and_create_pr` consumes the artifacts of every prior job. If `update_windows_version` did not upload an artifact, the PR-creation job fails on the missing artifact rather than opening a half-baked PR.
- **Dashboard surface**: existing — `gh run list --workflow=update_version.yml`. No new dashboards needed.

## Migration Plan

1. Land `p1-fix-windows-ci-tests` first (the Pester suite must exist to be tightened).
2. Land `p2-release-windows-image` ideally before this, so the Windows image is published; then this change extends what's published with version metadata.
3. Open a PR with:
   - `config/schema.cue` adding `#SemverQuad` and the `#Version.windows` field.
   - `config/version.json` backfilled with current values from `windows.Dockerfile`.
   - `windows.Dockerfile` ARGs without defaults.
   - `script/setEnvironmentVariables.js` exporting the new env vars.
   - `windows.yml` (and `release.yml` if `p2` landed) passing the new env vars as `--build-arg`.
   - `test/windows/Windows.Tests.ps1` reading the manifest and tightening assertions.
   - `update_version.yml` adding the `update_windows_version` job and merging its artifact in `update_docs_and_create_pr`.
4. PR's own `windows.yml` run is the verification. Green = the manifest values match the image; red = somebody mistyped one of the four values during backfill.
5. Merge.
6. Wait for the next scheduled `update_version.yml` run; it should produce a PR that includes a `windows` block diff. Review and merge as usual.
7. Rollback strategy: if `update_windows_version` produces consistently-bad PRs, mark it `if: false` in a follow-up PR. The schema and Dockerfile changes do not need rolling back; they are stable.

## Resolved Questions

- **`#SemverQuad` placement:** lives alongside `#SemverPatch` in `schema.cue`. `schema.cue` is 39 lines today; all five existing version primitives share the file, and there's no per-OS/per-domain split precedent. Splitting on Windows alone would invite drift (someone adds `#SemverQuint` to one file and forgets the other).
- **`vs_BuildTools.exe` URL as build arg:** no. The URL `https://aka.ms/vs/17/release/vs_buildtools.exe` embeds a single version token (`17` = VS 2022). A VS major-version bump (to `/vs/18/…`) is an out-of-band migration — component IDs change, the Pester assertions need rewriting, and `update_version.yml` cannot meaningfully automate it. Adding it as a build arg would be ceremony, not capability. A separate change handles VS 2025 if/when needed.
- **Commit `vsman` / channel manifest into the repo:** no. The channel manifest already SHA-256-pins `vsman`, so reproducibility-from-a-snapshot is built into Microsoft's design — committing it duplicates state Microsoft already authenticates. Forensic access is preserved by uploading both JSONs as workflow artifacts (90-day retention), which avoids polluting git history with vsman's frequent unrelated churn.

## Open Questions

- None blocking. The three above are resolved; the original "channel manifest as source" assumption was corrected during research (see Constraints: per-component versions live in `vsman`, not the channel — verified 2026-05-21).
