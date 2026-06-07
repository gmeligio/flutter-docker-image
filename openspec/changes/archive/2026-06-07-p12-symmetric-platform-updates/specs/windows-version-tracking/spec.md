## MODIFIED Requirements

### Requirement: Monthly upgrade PR includes Windows toolchain updates

The `update-version.yml` workflow SHALL include a job (`update-windows-version`) that attempts to update the `windows` block in `config/version.json` whenever it runs. The job SHALL:

- read the latest Git for Windows release from `https://api.github.com/repos/git-for-windows/git/releases/latest` and write the resolved version to `windows.git.version`,
- read VS BuildTools component versions from Microsoft's VS catalog manifest (`VisualStudio.vsman`) reached via the channel manifest at `https://aka.ms/vs/17/release/channel`,
- verify upstream consistency by comparing `channel.json.info.productSemanticVersion` against `vsman.json.info.productSemanticVersion`; on equality, write the extracted versions and emit a CUE-validated fragment artifact containing only the `windows` block,
- on inequality (Microsoft's release pipeline is mid-publish or otherwise inconsistent), skip the version write, emit a `windows_skipped=true` job output, and exit successfully without uploading a fragment artifact.

The job SHALL upload the raw `channel.json` and `vsman.json` it fetched as a `vs-manifests` workflow artifact on every run (regardless of skip vs. success), so the bytes that drove the decision are preserved for retroactive inspection.

The composed `version.json` consumed by `update-docs-and-create-pr` SHALL be produced by the dedicated `compose-version-manifest` job, not by `update-docs-and-create-pr` itself. When `update-windows-version` did not produce a fragment, `compose-version-manifest` SHALL carry forward the `windows` block from the base branch unchanged.

The experience context is the maintainer reviewing the monthly upgrade PR. They expect (a) Android and Windows toolchain bumps to appear in the same PR when both upstream sources are healthy, (b) the PR to still open with whichever platforms updated when others' upstreams are transiently inconsistent, (c) the PR body to make any skipped platform visible without having to dig through workflow logs, and (d) composition and validation to happen in dedicated jobs before any PR work begins.

#### Scenario: Monthly run produces a Windows-aware upgrade PR

- **GIVEN** a scheduled run of `update-version.yml` where Flutter has a new stable
- **AND** Git for Windows has a new release since the last run
- **AND** `channel.json.info.productSemanticVersion == vsman.json.info.productSemanticVersion`
- **WHEN** the workflow opens its upgrade PR
- **THEN** the composed `config/version.json` has a bumped `windows.git.version`
- **AND** the composed `config/version.json` has VS BuildTools versions extracted from `vsman.json.packages[]`
- **AND** `validate-config-version` exits 0 against the composed artifact

#### Scenario: No Windows update needed in this cycle

- **GIVEN** Git for Windows and VS BuildTools component versions match what is already in `config/version.json`
- **WHEN** the upgrade PR is composed
- **THEN** the PR still opens (because Flutter changed) but the `windows` block in the composed manifest is unchanged byte-for-byte

#### Scenario: Microsoft's channel and vsman disagree on release identity

- **GIVEN** a scheduled run of `update-version.yml`
- **AND** Microsoft serves a `channel.json` whose `info.productSemanticVersion` does not equal the `info.productSemanticVersion` in the `vsman.json` reachable from `channel.json.channelItems[…].payloads[0].url`
- **WHEN** `update-windows-version` runs its release-identity check
- **THEN** the job emits a `::warning::` annotation naming both versions
- **AND** the job exits successfully with `windows_skipped=true` as a job output
- **AND** the job uploads the fetched `channel.json` and `vsman.json` as the `vs-manifests` artifact
- **AND** no fragment artifact is uploaded

#### Scenario: PR opens with Windows skipped when upstream is inconsistent

- **GIVEN** `update-windows-version` produced `windows_skipped=true` for this run
- **AND** `update-flutter-version` and `update-android-version` produced their artifacts
- **WHEN** `compose-version-manifest` runs
- **THEN** the composed `config/version.json` contains the new `flutter` and new `android` blocks
- **AND** the `windows` block in the composed manifest is byte-for-byte identical to the `windows` block on the base branch
- **AND** the PR opens with the composed manifest
- **AND** the PR body contains a note explaining that the Windows toolchain was unchanged this cycle, with a link to the `update-windows-version` job log

#### Scenario: Forensic manifests are preserved on every run

- **GIVEN** any run of `update-version.yml`
- **WHEN** `update-windows-version` completes (whether success or skip)
- **THEN** a `vs-manifests` workflow artifact is uploaded containing the `channel.json` and `vsman.json` the job fetched
- **AND** the artifact is available for at least 90 days for retroactive inspection
