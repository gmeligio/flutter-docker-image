## Why

Today Renovate edits workflow files directly and `gx tidy` chases each PR with a fixup commit to sync `.github/gx.lock`. The two tools race on the same files, manifest specifiers (`^6`, `~0.3.0`) declared in `.github/gx.toml` are ignored, and Renovate can therefore propose a cross-major upgrade that the manifest was meant to forbid. Pointing Renovate at the manifest instead of the workflows turns `gx.toml` into the single source of truth for which action versions are allowed, and lets gx own propagation to the lock and workflow files.

## What Changes

- Disable Renovate's built-in `github-actions` manager so it stops editing files under `.github/workflows/` and `.github/actions/`.
- Add a Renovate `customManagers` regex entry that reads action specifiers from `.github/gx.toml` using the `github-tags` datasource and `npm` versioning (so `^6` and `~0.3.0` are honored).
- Move the existing monthly schedule from the `github-actions` package rule to a new rule that targets `.github/gx.toml`.
- Document that Renovate-driven action upgrades arrive as a `gx.toml`-only edit and are completed in-PR by the existing `gx.yml` `tidy` job.
- **BREAKING** for the spec only: the requirement that Renovate PRs already carry the lock update on open is replaced by a requirement that `gx.yml`'s `tidy` job pushes the lock and workflow updates onto the Renovate PR branch before merge.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `actions-version-tracking`: the "Renovate-driven upgrades keep the lock in sync" requirement is replaced with one that scopes Renovate to `.github/gx.toml` and assigns lock + workflow propagation to `gx tidy` running in CI on the PR branch.

## Impact

- Affected files: `.github/renovate.json` (rewrite), `openspec/specs/actions-version-tracking/spec.md` (delta applied during archive).
- No code changes; no changes to `.github/workflows/gx.yml`, `.github/gx.toml`, or `.github/gx.lock`.
- Operational impact: monthly Renovate PRs will edit one TOML line; the existing `gx.yml` `tidy` job adds a follow-up commit on the same PR with the lock and workflow updates. Net commit count per upgrade PR is unchanged or lower than today.
- Safety property gained: Renovate cannot propose a major-version upgrade unattended. Crossing a major now requires a human to edit `gx.toml` (`^6` → `^7`), which becomes the review surface.
