## Why

GitHub Actions in this repo are SHA-pinned today, but version policy lives only as `# v6.0.1` comments — there is no declarative manifest, no reproducible lock, and no CI gate that fails a PR which introduces an unpinned action. Adopting `gmeligio/gx` gives us a TOML manifest, a lock file, and a `gx lint` step that enforces pinning, while leaving Renovate to keep opening upgrade PRs.

## What Changes

- Add `gmeligio/gx` as the source of truth for GitHub Actions versions via `.github/gx.toml` (semantic constraints) and `.github/gx.lock` (resolved SHAs).
- Generate both files from the current SHA-pinned workflows using `gx init` (SHA-first resolution — no workflow rewrites required).
- Add a `gx lint` job to CI that fails the build when any `uses:` reference is unpinned or drifts from the lock.
- Teach Renovate-driven PRs to refresh the gx lock: add a post-update hook (or repo workflow) that runs `gx tidy` and amends the PR so workflows and lock stay in sync.
- Document the local workflow in `docs/contributing.md`: contributors who edit workflow files must run `gx tidy` before committing.

## Capabilities

### New Capabilities

- `actions-version-tracking`: Declarative manifest + lock for GitHub Actions, plus a CI lint that enforces SHA pinning and lock-file consistency on every PR.

### Modified Capabilities

<!-- None — no prior specs exist in openspec/specs/. -->

## Impact

- **Files added**: `.github/gx.toml`, `.github/gx.lock`.
- **Files modified**: `.github/workflows/ci.yml` (add `gx lint` job), `.github/renovate.json` (add `postUpgradeTasks` to run `gx tidy` on github-actions PRs), `docs/contributing.md` (workflow editing instructions).
- **Workflows touched**: read-only — `gx init` reads existing pins; lock + manifest are derived. No `uses:` line is rewritten.
- **Tooling**: contributors and CI need `gx` available. Install via `cargo install gx`, `brew install gmeligio/tap/gx`, or `jaxxstorm/action-install-gh-release` (already used elsewhere in this repo).
- **Renovate**: continues to open upgrade PRs for `github-tags` datasource. The `customManagers` regex for Debian deb packages in the Dockerfile is unaffected — gx does not handle that.
- **Risk**: lock-file drift if a Renovate PR merges without running `gx tidy`. Mitigated by `gx lint` failing CI when the lock and workflows disagree.
