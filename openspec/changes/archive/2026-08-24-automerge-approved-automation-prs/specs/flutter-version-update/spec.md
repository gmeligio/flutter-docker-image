## MODIFIED Requirements

### Requirement: Scheduled run opens an upgrade PR when a new stable Flutter is released

The `update-version.yml` workflow SHALL open exactly one pull request titled `chore(release): upgrade flutter to <version>` whenever the latest entry in `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` matching the stable channel and a `\d+.\d+.\d+` version differs from the version currently pinned in `config/version.json` (`.flutter.version`).

The workflow SHALL run on each weekday, so a new stable release is picked up within one business day of publication rather than waiting for a monthly cycle.

`config/version.json` is the single committed source of truth for the pinned Flutter version; there is no separate `config/flutter_version.json`. The change-detection anchor and the file the PR modifies are the same, so the automation can never delete an anchor a subsequent run depends on.

The experience context is the CI engineer who watches this repository for upgrade PRs to merge into their image fork.

#### Scenario: Upstream ships a new stable Flutter

- **GIVEN** `config/version.json` pins Flutter `X.Y.Z` (`.flutter.version == "X.Y.Z"`)
- **AND** the latest stable release in `releases_linux.json` is `X.Y.Z+1`
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** a branch `update-flutter-dependencies/X.Y.Z+1` is pushed
- **AND** a pull request is opened with title `chore(release): upgrade flutter to X.Y.Z+1`
- **AND** the commit message on that PR equals the title (non-empty)
- **AND** the PR diff does not delete `config/flutter_version.json` (the file does not exist)

#### Scenario: No upstream change since last run

- **GIVEN** `config/version.json` already pins the latest stable Flutter version
- **WHEN** the scheduled run of `update-version.yml` executes
- **THEN** no branch is created
- **AND** no pull request is opened
- **AND** all jobs after `update-flutter-version` are skipped
