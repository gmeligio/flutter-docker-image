## Context

`windows.Dockerfile` is built in two workflows that share most of their steps:

- `windows.yml` → `test-windows` (on `pull_request`): `clean-runner-disk` → ensure-daemon → read manifest → metadata → Docker Hub login (fork-gated) → `docker build --target test` → `docker run` (Pester).
- `release.yml` → `release-windows` (on tag push / `workflow_dispatch`): read manifest → metadata → three registry logins → `docker build --target flutter` → `docker push` to all three.

They have drifted. `release-windows` lacks `clean-runner-disk` and the daemon guard that `test-windows` has, and **neither** runs `harden-runner`. `windows-2025` runners now ship ~33 GB free on `C:` (the `D:` drive was removed), and the Windows image (servercore + full Flutter SDK + engine artifacts + VS Build Tools + Win11 SDK) overflows that during the VS Build Tools install — which is exactly how release run 27745938452 failed (`not enough space on the disk` at Step 21/36). The only thing keeping `test-windows` green is the `clean-runner-disk` step the release path is missing.

Constraints:
- `docker/build-push-action` does not support Windows containers (docker/build-push-action#18), so the build stays a raw `docker build` in PowerShell.
- `clean-runner-disk` (`ci-runner-disk-cleanup`) already dispatches by `runner.os` and asserts ≥40 GB free on `C:`; it is reused unchanged.
- `ci-workflow-hardening` requires harden-runner as the first step of every job and a top-level `permissions:` block on every workflow.
- Fork PRs have no secrets; the PR test path must build and test without any registry login.

## Goals / Non-Goals

**Goals:**
- One definition of the shared Windows build (cleanup, daemon guard, build-args, build) that both paths call, so they cannot drift.
- Fix the `release-windows` disk OOM by routing it through the same `clean-runner-disk` the PR path uses.
- Add `harden-runner` to the Windows path, bringing both jobs into `ci-workflow-hardening` compliance.
- Preserve every externally observable behavior: PR builds `--target test` + runs Pester; release builds `--target flutter` + pushes three registries with identical OCI labels; Android/Windows release parallelism; `workflow_dispatch` Windows-only rebuild; fork-PR safety.

**Non-Goals:**
- No change to `windows.Dockerfile`, the five build-args, or the published image contents.
- No promotion of harden-runner to `egress-policy: block` (stays `audit`, per the hardening spec's staged plan).
- No change to the Android/Linux build paths or to `clean-runner-disk` itself.
- No new disk-expansion tactic (larger runners, image slimming) — out of scope; the existing cleanup is sufficient and the assertion is the regression tripwire.

## Decisions

### Decision 1: Reusable workflow (`workflow_call`), not a composite action

The two units being consolidated are *whole jobs* with the same `runs-on`, `env`, and 8-step spine; they differ only in a short post-build tail. A reusable workflow consolidates the most — `runs-on`, `harden-runner`, `clean-runner-disk`, the daemon guard, and all five build-args become one definition edited once — and reduces each caller to ~5 lines.

*Alternative considered — composite action `build-windows-image`:* would still force each caller to re-declare `runs-on`, `env`, checkout, and harden-runner, weakening the "fix once, applies to both" property and the harden-runner consolidation. Rejected.

*Alternative considered — patch only (add the three missing steps to `release-windows`):* smallest diff, but leaves the duplication intact and lets the paths drift again on the next change. Rejected; the user explicitly chose consolidation.

### Decision 2: Parameterize with `target`, `push`, and `can-login`

- `target` (string): `test` or `flutter`, passed straight to `docker build --target`.
- `push` (boolean): selects the post-build tail — `false` runs the Pester container, `true` pushes the metadata tags. Also gates the GHCR and Quay logins (only the publish path needs them).
- `can-login` (boolean): gates the Docker Hub login so fork PRs (no secrets) skip it. Callers compute it: the PR caller passes `github.event.pull_request.head.repo.full_name == github.repository`; the release caller passes `true`.

`secrets: inherit` passes registry credentials from each caller, so the reusable workflow declares no explicit `secrets:` interface.

*Alternative considered — a single `mode: test|release` enum:* conflates two orthogonal axes (which target to build vs. whether secrets/push are available), and would not cleanly express the fork-PR `can-login=false, push=false` case. Rejected in favor of explicit booleans.

### Decision 3: Always compute three-registry metadata; push only when `push`

`docker/metadata-action` lists all three registry namespaces in both paths. On the test path the extra tags are local-only (never pushed) and one is used for `docker run`; on the release path all three are pushed. This keeps the metadata/label computation identical across paths, which is what the `windows-image-release` "labels match Android conventions" requirement depends on.

### Decision 4: Permissions and harden-runner placement under `workflow_call`

The reusable workflow declares a top-level `permissions: { contents: read }`. The **caller** job sets the broader scope it needs: the release caller declares `permissions: { contents: read, packages: write }` (effective token = intersection of caller and called), the PR caller leaves the default. `harden-runner` is the **first step of the called workflow's job** (where the runner actually executes); the `uses:` caller jobs run no steps of their own. This is the clarification `ci-workflow-hardening` needs so a reviewer does not flag the caller job as "missing harden-runner."

### Decision 5: Concurrency stays with the callers

`windows.yml` keeps its `cancel-in-progress: true` PR concurrency; `release.yml` keeps its serialized `cancel-in-progress: false` group. The reusable workflow (triggered only by `workflow_call`, never directly by `push`/`schedule`) declares no concurrency, consistent with `ci-workflow-hardening` (which scopes the concurrency requirement to push/schedule-triggered workflows).

## Automated Test Strategy

There is no unit-test harness for workflows; verification is layered:
- **Static:** `gx lint` (the repo's workflow policy gate) must pass on the new `windows-image.yml` and the two edited callers — covering SHA-pinning, `permissions:` presence, and harden-runner placement. YAML-parse all three files and confirm every `uses:` resolves and every `inputs.*`/`secrets` reference is defined.
- **PR path (self-testing):** this change is itself a PR, so `windows.yml` → `test-windows` runs the consolidated workflow end-to-end on `windows-2025`: `clean-runner-disk` runs, the image builds `--target test`, and Pester passes. A green `test-windows` check on this PR is the primary functional gate.
- **Fork-safety:** confirm (by reading the resolved `can-login`/`push` gates) that with `can-login=false, push=false` no login step executes — the critical path for contributor PRs.
- **Release path (deferred):** the `release-windows` publish can only be fully verified on the first tag push after merge — the image must build past Step 21/36 (VS Build Tools) without OOM and push to all three registries. This is the deferred runtime gate, mirrored on `workflow_dispatch` for a one-off rebuild if needed.

## Observability

- **Disk regression** is surfaced loudly by the reused `clean-runner-disk` assertion: if post-clean free space on `C:` drops below 40 GB the cleanup step fails with the actual free space and the top remaining directories — at the cleanup step, not 20 minutes later inside `docker build`. The one-line job summary (`clean-runner-disk: freed X GB …`) records freed bytes per run for trend comparison.
- **The original failure mode** (`not enough space on the disk` deep in VS Build Tools) cannot recur silently: either cleanup frees enough and the build proceeds, or the assertion fails first with a typed message.
- **Egress** on the Windows build is now visible via harden-runner's audit summary (registries, mirrors, action endpoints) — previously invisible on this path.
- **Build/push failures** propagate via `$LASTEXITCODE` checks in the PowerShell tail (unchanged from today), so a failed `docker build` or `docker push` fails the job with a non-zero exit rather than a silent pass.

## Risks / Trade-offs

- **[Reusable-workflow permissions intersection drops `packages: write`]** → the release caller job must declare `permissions: { contents: read, packages: write }`; verified by a successful GHCR push on the deferred release run (and by reading the caller job's `permissions:` block).
- **[Fork PR accidentally attempts a login and fails]** → `can-login`/`push` gating is computed by the caller and asserted by inspection; the PR path with `can-login=false` skips Docker Hub login entirely.
- **[harden-runner audit perturbs the Windows build]** → audit mode only records egress, it does not block; if it misbehaves on `windows-2025` the fallback is a scoped exemption in `.github/gx.toml` (the mechanism `ci-workflow-hardening` already defines), not reverting the consolidation.
- **[Nested logs reduce at-a-glance readability]** → the caller job still reports a single red/green check on the PR/release; the run summary and harden-runner insights remain one tab away. Acceptable trade for a single source of truth.
- **[Deferred release verification]** → the release path is only exercised on tag push; mitigated by the PR path exercising the identical build (minus push) on every PR, and by `workflow_dispatch` allowing a manual rebuild without re-cutting the tag.

## Migration Plan

1. Add `.github/workflows/windows-image.yml` (`workflow_call`) carrying the full shared build + tail.
2. Replace `windows.yml`'s `test-windows` steps with a caller (`target: test`, `push: false`, `can-login` computed, `secrets: inherit`).
3. Replace `release.yml`'s `release-windows` steps with a caller (`target: flutter`, `push: true`, `can-login: true`, `secrets: inherit`, `permissions: packages: write`).
4. Update specs: add `windows-image-build`; restate `windows-image-testing`, `windows-image-release`, and the `ci-workflow-hardening` harden-runner requirement.
5. Open the PR; `test-windows` (now the consolidated path) must be green before merge.

**Rollback:** revert the three workflow files; the deleted inline steps are recoverable from git history. The image and registries are unaffected by a rollback (no Dockerfile or tag-scheme change).

## Open Questions

None blocking. If harden-runner audit proves noisy on `windows-2025`, decide later whether to keep `audit` or add a scoped `gx.toml` note — out of scope for this change.
