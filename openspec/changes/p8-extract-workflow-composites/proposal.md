## Why

Across the 11 workflows in `.github/workflows/`, two step sequences are repeated almost verbatim and account for ~150 lines of duplication:

1. **Checkout + mise setup + read environment variables from `config/version.json`** — appears in `build.yml:52-64`, `ci.yml:23-44`, `changelog.yml:16-37`, `release.yml:26-38`, `release.yml:106-115`, `tag.yml:16-37`, `update_docs.yml:16-35`, `windows.yml:20-45`, `update_version.yml:40-44`, `update_version.yml:92-96`, `update_version.yml:211-232`, `update_version.yml:333-394`. That is **12 copies of the same 3-step block** across 9 files.
2. **Docker registry login fan-out (GHCR + Docker Hub, sometimes Quay)** — appears in `build.yml:74-87`, `ci.yml:26-30`, `release.yml:56-74`, `release.yml:230-238`, `windows.yml:29-46`. Each copy gates Docker Hub login behind `if: github.event.pull_request.head.repo.full_name == github.repository` to keep secrets out of fork PRs (the pwn-request defense codified in p7).

The duplication has three concrete costs the maintainer notices:
- Bumping the `actions/checkout` or `jdx/mise-action` SHA touches 9 files instead of 1.
- The fork-secret gate on Docker Hub login is replicated by hand; a future maintainer can easily forget it on a new workflow and leak the secret.
- When `config/version.json` schema changes, the `setEnvironmentVariables.js` call site must be updated in every workflow.

This change extracts both sequences into composite actions under `.github/actions/`. p7 (workflow hardening) lands first; this change preserves every permission, concurrency, and harden-runner addition p7 introduces.

## What Changes

- **Add composite action `.github/actions/setup-build-context/action.yml`** that runs: (a) `actions/checkout`, (b) `jdx/mise-action`, (c) `actions/github-script` calling `script/setEnvironmentVariables.js`. Inputs: `fetch-depth` (default `1`), `fetch-tags` (default `false`). Outputs: the env vars set by the script (passed through via `core.setOutput`).
- **Add composite action `.github/actions/docker-registry-login/action.yml`** that performs: GHCR login (always, using `GITHUB_TOKEN`), Docker Hub login (gated on `inputs.push-to-dockerhub == 'true'` AND a `secrets`-equivalent passed in), Quay login (gated on `inputs.push-to-quay == 'true'`). The composite action SHALL document that the **caller** is responsible for the fork-secret gate — composite actions cannot read `secrets.*` directly, so the gate stays at the calling job level. Document this constraint loudly to avoid a regression.
- **Rewrite all 12 setup-block call sites** in workflows to call `uses: ./.github/actions/setup-build-context` with the appropriate inputs.
- **Rewrite all 5 docker-login call sites** to call `uses: ./.github/actions/docker-registry-login`.
- Net line reduction: ~120 lines of YAML, with the gain that bumping an underlying action SHA now touches one file.
- File naming: composite-action directories use **hyphens, not underscores** (`setup-build-context`, `docker-registry-login`). No leading-underscore prefix.

## Capabilities

### New Capabilities

- `ci-workflow-composites`: defines the contract that the two composite actions SHALL satisfy — input shape, output shape, behavior under fork PRs (login composite), and the rule that all workflow setup goes through them.

### Modified Capabilities

- `ci-workflow-hardening` (added in p7): tighten the "every job declares harden-runner" requirement to clarify that composite actions also start with harden-runner so they cannot be a back-door.

## Impact

- **Affected files**: every workflow under `.github/workflows/`; two new composite actions under `.github/actions/`.
- **Behavioral change**: none observable to image users or to Scorecard. Workflow runs perform the same steps in the same order; only the YAML source moves.
- **Risk**: a composite-action regression now affects every workflow at once. Mitigation: ship behind a draft PR that re-runs `build.yml`, `ci.yml`, `release.yml` (workflow_dispatch), `windows.yml`, and one `update-version.yml` job before merge. Compare step-by-step logs against the pre-change baseline.
- **Risk**: contributors unfamiliar with composite actions may copy a workflow and inline the steps again. Mitigation: add a note in `.github/workflows/SECURITY.md` (added in p7) requiring the composite for new workflows.
- **Depends on**: `p7-harden-workflow-permissions` archived. p7 introduces the harden-runner contract; this change extends it into composites.
- **Out of scope**: reusable workflows for image build (p9), file renames (p9).
