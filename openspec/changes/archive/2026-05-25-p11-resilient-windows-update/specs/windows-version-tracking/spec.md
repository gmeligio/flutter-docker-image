## MODIFIED Requirements

### Requirement: Monthly upgrade PR includes Windows toolchain updates

The `update_version.yml` workflow SHALL include a job (`update_windows_version`) that attempts to update the `windows` block in `config/version.json` whenever it runs. The job SHALL:

- read the latest Git for Windows release from `https://api.github.com/repos/git-for-windows/git/releases/latest` and write the resolved version to `windows.git.version`,
- read VS BuildTools component versions from Microsoft's VS catalog manifest (`VisualStudio.vsman`) reached via the channel manifest at `https://aka.ms/vs/17/release/channel`,
- verify upstream consistency by comparing `channel.json.info.productSemanticVersion` against `vsman.json.info.productSemanticVersion`; on equality, write the extracted versions and emit a CUE-validated `version.json.windows` artifact,
- on inequality (Microsoft's release pipeline is mid-publish or otherwise inconsistent), skip the version write, emit a `windows_skipped=true` job output, and exit successfully without uploading the `version.json.windows` artifact.

The `update_docs_and_create_pr` job SHALL tolerate a missing `version.json.windows` artifact: when absent, the existing committed `windows` block in `config/version.json` is carried forward unchanged into the upgrade PR, and the PR body includes a note explaining that the Windows toolchain was unchanged this cycle.

The `update_windows_version` job SHALL upload the raw `channel.json` and `vsman.json` it fetched as a `vs-manifests` workflow artifact on every run (regardless of skip vs. success), so the bytes that drove the decision are preserved for retroactive inspection.

The experience context is the maintainer reviewing the monthly upgrade PR. They expect (a) Android and Windows toolchain bumps to appear in the same PR when both upstream sources are healthy, (b) the PR to still open with Flutter+Android updates when Microsoft's VS manifest is transiently inconsistent, and (c) any decision to skip the Windows bump to be visible without having to dig through the workflow logs.

#### Scenario: Monthly run produces a Windows-aware upgrade PR

- **GIVEN** a scheduled run of `update_version.yml` where Flutter has a new stable
- **AND** Git for Windows has a new release since the last run
- **AND** `channel.json.info.productSemanticVersion == vsman.json.info.productSemanticVersion`
- **WHEN** the workflow opens its upgrade PR
- **THEN** the PR's `config/version.json` has a bumped `windows.git.version`
- **AND** the PR's `config/version.json` has VS BuildTools versions extracted from `vsman.json.packages[]`
- **AND** the PR's `config/version.json` passes `cue vet` against `#Version`

#### Scenario: No Windows update needed in this cycle

- **GIVEN** Git for Windows and VS BuildTools component versions match what is already in `config/version.json`
- **WHEN** the upgrade PR is composed
- **THEN** the PR still opens (because Flutter changed) but the `windows` block is unchanged byte-for-byte

#### Scenario: Microsoft's channel and vsman disagree on release identity

- **GIVEN** a scheduled run of `update_version.yml`
- **AND** Microsoft serves a `channel.json` whose `info.productSemanticVersion` does not equal the `info.productSemanticVersion` in the `vsman.json` reachable from `channel.json.channelItems[…].payloads[0].url`
- **WHEN** `update_windows_version` runs its release-identity check
- **THEN** the job emits a `::warning::` annotation naming both versions
- **AND** the job exits successfully with `windows_skipped=true` as a job output
- **AND** the job uploads the fetched `channel.json` and `vsman.json` as the `vs-manifests` artifact
- **AND** no `version.json.windows` artifact is uploaded

#### Scenario: PR opens with Windows skipped when upstream is inconsistent

- **GIVEN** `update_windows_version` produced `windows_skipped=true` for this run
- **AND** `update_flutter_version` and `update_android_version` produced their artifacts successfully
- **WHEN** `update_docs_and_create_pr` composes the upgrade PR
- **THEN** the PR opens with Flutter and Android updates merged into `config/version.json`
- **AND** the `windows` block in the PR's `config/version.json` is byte-for-byte identical to the `windows` block on the base branch
- **AND** the PR body contains a note explaining that the Windows toolchain was unchanged this cycle, with a link to the `update_windows_version` job log

#### Scenario: Forensic manifests are preserved on every run

- **GIVEN** any run of `update_version.yml`
- **WHEN** `update_windows_version` completes (whether success or skip)
- **THEN** a `vs-manifests` workflow artifact is uploaded containing the `channel.json` and `vsman.json` the job fetched
- **AND** the artifact is available for at least 90 days for retroactive inspection
