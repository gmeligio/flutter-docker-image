# Workflow security policy

This document defines the security rules every file under `.github/workflows/` and `.github/actions/` SHALL satisfy. Vulnerability reporting lives in [`.github/SECURITY.md`](../SECURITY.md); this file covers workflow authoring.

The rules below are derived from the OpenSpec `ci-workflow-hardening` capability (`openspec/specs/ci-workflow-hardening/spec.md`). Edit the spec first; this file is the contributor-facing summary.

## 1. No `pull_request_target` without a security review

The `pull_request_target` trigger runs in the **base repository's** security context with full access to secrets and a write-scoped `GITHUB_TOKEN`. Combined with `actions/checkout` of the PR HEAD, it forms the "pwn request" attack class documented by [JFrog](https://research.jfrog.com/post/part-1-pull-request-target-exploitation/), [StepSecurity](https://www.stepsecurity.io/blog/github-actions-pwn-request-vulnerability), and [Wiz](https://www.wiz.io/blog/github-actions-security-threat-model-and-defenses). It was exploited in the May 2026 [TanStack npm supply-chain compromise](https://tanstack.com/blog/npm-supply-chain-compromise-postmortem).

Rules:

- No workflow in this repo uses `pull_request_target` at the time of writing. Adding one requires an OpenSpec change proposal whose `proposal.md` documents the threat model.
- Privileged workflows (any access to secrets or write-scoped `GITHUB_TOKEN`) MUST NOT check out `${{ github.event.pull_request.head.sha }}` or `${{ github.head_ref }}`.
- If untrusted PR contents must be processed with privileges, use the two-workflow split: an `on: pull_request` workflow that builds without secrets and uploads an artifact, then an `on: workflow_run` workflow that downloads and post-processes it with the privileges.

## 2. Third-party actions are SHA-pinned and version-consistent

Every `uses:` of a third-party action MUST pin to a 40-character commit SHA with a trailing `# v<semver>` comment. The same action used in multiple workflows MUST pin to the same SHA across the repo — drift signals an incomplete update.

`gx` (`.github/gx.toml`, `.github/gx.lock`) enforces the pinning side of this rule; the cross-workflow consistency is enforced by review and by `gx`'s shared resolution.

## 3. Prefer GitHub App tokens over PATs for cross-repo writes

Where a workflow must push commits, create tags, or comment cross-repo, generate a GitHub App installation token via `actions/create-github-app-token` (using the `VERIFIED_COMMIT_*` secrets) instead of a long-lived Personal Access Token. App tokens are scoped, time-limited, and rotatable without re-issuing a PAT.

## 4. Every job starts with `harden-runner`

Every job in every Linux workflow MUST declare `step-security/harden-runner` as its first step, with `egress-policy: audit` at minimum. Audit mode records every outbound network call without blocking, so a compromised action's exfiltration shows up in the job's egress summary tab.

Windows jobs are exempt — `harden-runner` does not support `windows-2025` runners.

Promotion to `egress-policy: block` happens per job in a follow-up change once an egress baseline is established.

## 5. Minimum-scope `permissions:` at workflow level

Every workflow MUST declare a top-level `permissions:` block. The default scope MUST be `contents: read`. Any broader scope MUST be declared at the job level on the specific job that needs it, with a comment naming why.

## 6. `concurrency:` on push-triggered shared-state workflows

Every workflow triggered by `push:` or `schedule:` that mutates shared state (commits, tags, image registries) MUST declare a top-level `concurrency:` block grouped on `${{ github.workflow }}-${{ github.ref }}`.

- Release-path workflows (pushes commits, tags, images): `cancel-in-progress: false` — serialize, do not cancel.
- CI workflows (validate only): `cancel-in-progress: true` — latest commit wins.
