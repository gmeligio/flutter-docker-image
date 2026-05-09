## MODIFIED Requirements

### Requirement: Renovate-driven upgrades keep the lock in sync

Renovate SHALL be configured to manage GitHub Action versions exclusively through `.github/gx.toml`, not by editing workflow files. The repository's CI SHALL propagate every Renovate-driven `gx.toml` edit through to `.github/gx.lock` and the workflow files on the same pull request branch before merge, so that when the PR is merged the manifest, lock, and workflow `uses:` SHAs are mutually consistent.

#### Scenario: Renovate edits the manifest only

- **WHEN** Renovate opens an upgrade PR for a GitHub Action
- **THEN** the only file modified by Renovate's commit is `.github/gx.toml`
- **AND** the modification is a change to the action's specifier (e.g., `"^6.0.1"` → `"^6.0.2"`, or `"^6"` → `"^6"` with no change if already the broadest in-major specifier)

#### Scenario: gx.yml propagates the manifest edit on the PR branch

- **WHEN** a PR contains a `.github/gx.toml` edit and the workflow `uses:` SHAs do not yet match the new specifier
- **THEN** the `gx.yml` workflow's `tidy` job runs `gx tidy`, regenerates `.github/gx.lock`, rewrites every affected `uses: <owner>/<repo>@<sha> # vX.Y.Z` reference in `.github/workflows/**` and `.github/actions/**`, and pushes the resulting changes onto the PR branch as a single commit
- **AND** `gx lint` passes on the resulting head commit

#### Scenario: Manifest specifier bounds the upgrade

- **WHEN** a new major version of an action is published upstream and the manifest specifier is `^N` for the prior major
- **THEN** Renovate does not propose an upgrade that crosses the major boundary
- **AND** crossing the major requires a human commit that changes `.github/gx.toml` from `^N` to `^N+1`, after which `gx tidy` resolves the new major and rewrites lock and workflow files on the same PR

#### Scenario: Renovate's built-in github-actions manager is disabled

- **WHEN** Renovate evaluates this repository
- **THEN** the built-in `github-actions` manager is disabled by configuration
- **AND** no Renovate run produces a commit that edits any file under `.github/workflows/` or `.github/actions/`

#### Scenario: Lock drift is detected before merge

- **WHEN** for any reason a Renovate PR's head commit lacks the lock and workflow updates that match its `gx.toml` edit
- **THEN** the `gx lint` CI job fails the PR
- **AND** merge is blocked until `gx tidy` is run and committed
