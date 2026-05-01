## Context

Today, every `uses:` reference in `.github/workflows/*.yml` is pinned to a 40-character commit SHA with a trailing `# vX.Y.Z` comment. Pinning is enforced informally: a reviewer notices an unpinned PR. There is no manifest of intended versions, no lock with auditable timestamps, and no automated check.

Renovate (`.github/renovate.json`) opens monthly grouped PRs against the `github-tags` datasource and a `customManagers` regex covers Debian deb packages in the Dockerfile. ~16 distinct actions are in use across 8 workflows.

`gmeligio/gx` is a Rust CLI by the same author as this repo. Its **SHA-first resolution** strategy means it can read the existing pins and reconstruct a manifest + lock without modifying any workflow line. It is distributed via Homebrew, Cargo, and pre-built GitHub releases.

## Goals / Non-Goals

**Goals:**

- A single declarative source of truth for the GitHub Actions versions this repo depends on.
- Reproducible installs: any contributor or CI run can resolve the same SHA for the same constraint.
- Fail PRs that introduce unpinned actions.
- Keep Renovate's PR automation — gx complements rather than replaces it.

**Non-Goals:**

- Replacing the existing `config/version.json` machinery for Flutter / Android / Fastlane SDKs (different domain, different update cadence).
- Replacing Renovate's Dockerfile `customManagers` regex for Debian deb packages.
- Authoring an upgrade-PR bot from scratch (`gx upgrade` is run manually or via a follow-up cron change).

## Decisions

### Decision 1: Adopt gx in file-backed mode (manifest + lock)

`gx` supports a memory-only mode (one-off `gx tidy`), but we want team-level reproducibility and a CI lint gate, both of which require the manifest + lock. Generate them with `gx init`.

**Alternative considered**: stay memory-only. Rejected — without a lock, `gx lint` cannot detect drift, and version constraints can't be expressed (`^6` vs the literal SHA in workflows).

### Decision 2: Keep Renovate, add gx as authority

Renovate continues to open the monthly upgrade PR. After bumping a SHA, it must run `gx tidy` so `.github/gx.lock` matches the updated workflow. Implementation options:

- (a) `postUpgradeTasks` in `renovate.json` (recommended — one place, runs as part of the same PR).
- (b) A separate workflow listening on PR open that runs `gx tidy` and pushes a fixup commit.

Pick (a). It is supported by Renovate self-hosted and by the GitHub-hosted app for repositories that allow it; if the GitHub-hosted Renovate app blocks `postUpgradeTasks`, fall back to (b).

**Alternative considered**: Replace Renovate's `github-tags` datasource with a `gx upgrade` cron workflow that opens PRs via `peter-evans/create-pull-request` (already used in `update_version.yml`). Rejected for the initial migration — Renovate's release-notes integration and grouping are valuable; we can revisit if the postUpgradeTasks hook proves brittle.

### Decision 3: Install gx in CI via the existing `jaxxstorm/action-install-gh-release`

That action is already used in `build.yml`, `ci.yml`, `changelog.yml`, `update_version.yml`. Reuse for gx — no new tooling pattern.

**Alternative considered**: `cargo install gx`. Rejected — adds a Rust toolchain dependency to CI for a single binary.

### Decision 4: Manifest version constraints default to caret on major (e.g., `^6`)

Mirrors the manifest gx itself ships in its own repo. Lets patches and minor versions auto-resolve while requiring a deliberate change for majors. Where the current pin is on a v0 action (e.g., `peter-evans/dockerhub-description@v4` is v4 but some actions are v0/v1) or a known-unstable action, pin tighter (`~1.18.2`).

### Decision 5: `gx lint` is a required CI check

Add a job to `.github/workflows/ci.yml` that runs on every PR. It must:

- Fail if any `uses:` is not SHA-pinned.
- Fail if `.github/gx.lock` does not match the SHAs in the workflows.

This is the gate that makes the manifest meaningful.

## Risks / Trade-offs

- **Lock-file drift if Renovate edits a SHA without running `gx tidy`** → `gx lint` fails the PR; reviewer or Renovate's `postUpgradeTasks` re-runs `gx tidy`. Worst case: a one-line manual fix.
- **gx is a young tool (one author, this user)** → Adoption risk is low because the user owns both repos, but document a rollback path: deleting `.github/gx.toml` and `.github/gx.lock` and removing the lint job restores the prior state — workflows are unchanged.
- **`postUpgradeTasks` may be disabled on the GitHub-hosted Renovate app** → Fall back to a small `gx-tidy.yml` workflow triggered on `pull_request` that runs `gx tidy` and pushes a fixup commit when the lock drifts.
- **Network dependency at lint time** → `gx lint` against the lock should be offline; only `gx upgrade` hits the GitHub API. Verify during implementation; if `gx lint` requires API calls, configure `GITHUB_TOKEN` for the CI step.
- **Two tools touching the same files** → Mitigated by Decision 2: gx runs *after* Renovate inside the same PR, never in parallel.

## Automated Test Strategy

- **Manifest generation correctness**: After `gx init`, run `gx lint` locally — expect zero diff. Commit only if clean.
- **CI integration test**: Open a draft PR that intentionally bumps an action's SHA without updating the lock. Confirm `gx lint` fails. Then run `gx tidy`, push, and confirm green.
- **Renovate integration test**: Manually trigger a Renovate run against a test branch (or wait for the next scheduled run after merge); verify the PR includes both workflow SHA changes and `.github/gx.lock` updates.
- **Critical path**: the lint job in CI. If it can't reliably distinguish "pinned and locked" from "unpinned or drifted," the manifest provides no value.
- **No new test infrastructure** is needed — existing CI runners and the standard GitHub Actions PR flow cover everything.

## Observability

- `gx lint` writes its diagnostics to stdout/stderr; CI annotations surface them on the PR.
- Failure modes that could be silent:
  - **Renovate `postUpgradeTasks` not running** (e.g., disabled on hosted Renovate). Mitigation: `gx lint` will catch it on the PR — failure is loud, not silent.
  - **`gx lint` skipped due to a workflow filter mistake**. Mitigation: in code review of `ci.yml`, verify the gx-lint job has no `if:` exclusions and runs on all PRs touching `.github/**`.
- Log retention is GitHub's default (90 days for workflow logs) — sufficient for after-the-fact triage.

## Migration Plan

1. Install `gx` locally; run `gx init` to generate `.github/gx.toml` and `.github/gx.lock`.
2. Run `gx tidy` — expect a no-op diff. Commit both files.
3. Add the `gx lint` job to `.github/workflows/ci.yml`. Open a PR; confirm green.
4. Add `postUpgradeTasks` (or fallback workflow) to keep Renovate PRs in sync.
5. Update `docs/contributing.md` with the local workflow.
6. Monitor the next Renovate-driven PR; verify `gx tidy` runs and the lock updates correctly.

**Rollback**: revert the change. Workflow files were never modified, so deletion of `.github/gx.toml`, `.github/gx.lock`, and the lint job restores prior state.

## Open Questions

- Does the GitHub-hosted Renovate app permit `postUpgradeTasks`? Verify against current Mend/Renovate documentation before committing to Decision 2(a). If blocked, ship 2(b) directly.
- Should the `gx lint` job run on the `main` push as well as PRs? Defer — PR-only is sufficient for the gate; main-push lint can be added later if drift somehow lands.
