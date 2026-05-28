## Why

The `scan_image` job's `docker/scout-action` step is the single biggest contributor to PR wall-clock — **9m31s of a 20m51s critical path** on a warm-cache PR (run 25877980895). That is ~46% of the gating time spent in a check whose results are advisory: `only-fixed: true` already implies the maintainer cares about it but won't block merge on it.

Measured step breakdown on that run:

| Step | Duration |
|---|---|
| `Scan with Docker Scout` (compare + recommendations) | **9m 31s** |
| `Clean runner disk` | 4m 46s |
| `Test image` (container-structure-test) | 4m 26s |
| `Build image` (warm cache) | 1m 48s |

Docker Scout's per-scan time is dominated by **step 1 of its analysis pipeline: indexing the image's filesystem to extract a Software Bill of Materials** ([docs.docker.com/scout/explore/analysis](https://docs.docker.com/scout/explore/analysis/)). For this repo's image (Flutter + Android SDK + NDK, ~5 GB extracted), that means walking every layer of every stage on every PR. Scout's docs are explicit about the alternative: *"When an image includes an SBOM attestation, Docker Scout uses it instead of generating one."*

The build today produces no attestations. The `docker/build-push-action` step (`build.yml:127`) sets `outputs: type=docker` (local-load only) and does the GHCR push as a separate `docker push` step (`build.yml:157`–`162`). That separation is incompatible with build-time attestations — provenance and SBOM attestations are produced by buildx during the push to a registry, not by a follow-up `docker push`.

### A constraint we surfaced mid-investigation

Docker Scout DSOS integrates natively with Docker Hub repos, ECR, ACR, and Artifactory — **not GHCR** ([Scout integrations](https://docs.docker.com/scout/integrations/)). Per the [DSOS docs](https://docs.docker.com/docker-hub/repos/manage/trusted-content/dsos-program/), Scout entitlements are tied per Docker Hub repository: pushes to a Scout-enabled Docker Hub repo trigger automatic analysis, and that analysis is what anchors env streams. GHCR pushes are invisible to Scout's analysis backend.

This meant the original `to-env: prod` setup required the source image's repository name to match a Docker-Hub-indexed repo, which forced one of two complications:

1. **Dual-push to both GHCR and Docker Hub on every PR** (initially attempted): preserves env-stream tracking but adds Docker Hub credentials in CI, doubles the upload, and adds a Docker Hub cleanup mirror to `cleanup_pr_image.yml`. The cleanup needs a Docker Hub PAT with Delete scope (OATs are rejected by the relevant endpoint — see [docker/hub-feedback#2445](https://github.com/docker/hub-feedback/issues/2445)).
2. **Re-anchor env to GHCR**: not possible because Scout has no GHCR integration.

Both paths were wrong responses to the constraint. The correct response is to **drop the env-stream lookup** and use Scout's pinned-target compare semantic.

This change moves the GHCR push into the `docker/build-push-action` step with `sbom: true, provenance: mode=max` (attestations attached at build time, SBOM consumed by Scout via `registry://...@<digest>`), and replaces `to-env: prod` with `to: ghcr.io/<owner>/flutter-android:<latest-release>`. The latest-release tag is already computed by the existing `setup` job (`build.yml:20`–`36`), which reads `gh api releases/latest`.

This change is justified for a spec because the **maintainer's PR check page experience changes**: the `scan_image` step's wall-clock drops sharply (Scout reads the attached SBOM instead of indexing), and the path by which Scout obtains both source and target metadata becomes "registry-attached attestation on GHCR" — a structural property worth pinning down so it doesn't silently regress into the env-stream entanglement.

### Where this leaves Docker Hub

The release flow (`release.yml`) continues to publish stable releases to Docker Hub unchanged. Docker Hub's public page for `gmeligio/flutter-android` continues to show Scout-driven vulnerability data on released tags (the per-Docker-Hub-repo Scout entitlement auto-analyzes those pushes). Only the PR-time scan path is GHCR-only; the consumer-facing Docker Hub page is unaffected.

## What Changes

- **`.github/workflows/build.yml` — `Load image metadata`**: `images:` is a single entry `ghcr.io/<owner>/flutter-android`; `tags:` is the handoff tag (`pr-<N>` or `branch-<ref>`). No Docker Hub namespace.
- **`.github/workflows/build.yml` — `Build image` step** is split into two `if:`-gated steps:
  - **Step A** (non-fork): `push: true`, `sbom: true`, `provenance: mode=max`, no `outputs:`. Single registry push (GHCR) with attestations.
  - **Step B** (fork): `outputs: type=docker`, no push, no attestations. `scan_image` is already skipped for forks per `ci-parallel-image-validation`.
- **Delete** the standalone `Push image to GHCR` step — buildx Step A handles the push.
- **`Re-tag image for local handoff`** is `if:`-gated to forks only (non-fork pushes straight to GHCR; no local copy exists; `test_image` pulls from GHCR).
- **`.github/workflows/build.yml` — `Scan with Docker Scout` step**:
  - `command:` is `compare` only — drop `recommendations` (operationally unused; base-image refresh is Renovate's job).
  - `image:` is `registry://ghcr.io/<owner>/flutter-android@<digest>` — digest emitted by Step A, carries the SBOM attestation Scout consumes.
  - `to:` is `ghcr.io/<owner>/flutter-android:<latest-release-tag>` — sourced from `needs.setup.outputs.flutter_version`. Replaces `to-env: prod`.
  - Drop `organization:` (only required for env-stream and latest-indexed comparisons).
  - Drop `Login to Docker Hub` step entirely.
  - Add `Login to GHCR` (for Scout to pull both source and target from GHCR).
  - Add `needs: setup` to the job (was `needs: build_image` only).
- **Delete** the `Pull image and re-tag for Scout` step and the fork artifact-load steps from `scan_image` — `registry://` reads directly from GHCR; fork-PR scan is job-level skipped.
- **`build_image.outputs.image_digest`** added — sourced from Step A's `digest` output. Safe from secret-masking (a `sha256:…` value does not contain the `DOCKER_HUB_USERNAME` secret string).
- **No change** to `only-fixed: true` (existing). No new filter flags added (`only-severities`, `ignore-base`, `ignore-unchanged`) — the goal is faster scans, not narrower ones.
- **No change** to required-check configuration; Scout output remains advisory.
- **No change** to `release.yml`'s Docker Hub publishing — release flow is untouched, public Docker Hub page continues to show Scout vulnerability data.
- **No change** to `cleanup_pr_image.yml` — GHCR-only PR builds use the existing GHCR cleanup path. No Docker Hub tag cleanup needed.

## Capabilities

### New Capabilities

- `ci-image-vulnerability-scan`: contract for how the Docker Scout step obtains the image's package metadata (registry-attached SBOM attestation, not runner-side indexing), how the comparison target is sourced (pinned latest-release tag, not env stream), and the explicit non-gating posture.

### Modified Capabilities

- `ci-image-build-cache`: the `docker/build-push-action` step is the sole producer of GHCR image manifests; push + attestations are emitted in one buildx invocation, not a separate `docker push`.

## Impact

- **Affected files**: `.github/workflows/build.yml` only. No Docker Hub coupling added to any other workflow; `cleanup_pr_image.yml` is unchanged from main.
- **Behavioral change for the maintainer**: Scout step duration drops materially. The PR comment shows the same `compare` output as today (delta vs latest release), without the `recommendations` block (which has never driven a base-image bump in this repo).
- **Behavioral change for image consumers**: GHCR images now carry SBOM and provenance attestations queryable via `docker buildx imagetools inspect`. The Docker Hub public page is unchanged — release pushes continue to populate it.
- **Behavioral change for Scout dashboard users**: The PR-time scans do not create persistent records in Scout's analysis history (no GHCR integration). The Docker Hub repo's release-time analysis continues to populate the dashboard. The `prod` env stream becomes operationally orphaned and can be retired in the Scout dashboard at leisure — nothing in CI references it after this change.
- **Risk**: `sbom: true` + `provenance: mode=max` produce an OCI image index. Some legacy registries and older Docker daemons cannot pull image-index references; GHCR and Docker >= 23 are fine. The repo's documented minimum Docker version is well above 23.
- **Risk**: switching the Scout step from `local://` to `registry://ghcr.io/…@<digest>` means Scout no longer reads the local Docker daemon copy. If the GHCR push fails partway, Scout would scan a stale or nonexistent ref. Mitigation: buildx Step A pushes atomically; partial push means step failure means `scan_image`'s `needs:` chain fails. `image_digest` output is empty on fork (no push), and `scan_image` is `if:`-gated off for forks.
- **Risk**: the comparison target (`to: ghcr.io/<owner>/flutter-android:<release-tag>`) requires the release tag to exist on GHCR. Release-time publishing to GHCR has been in place throughout p1–p11; if a release tag is missing on GHCR, Scout's `compare` fails. Mitigation: the PR that bumps `config/version.json` runs before the release tag is published, so on that specific PR the target is the *previous* release — still valid. Continuous release workflow keeps the target tag fresh.
- **Depends on**: `p9-consolidate-image-build-workflows` is **not** a blocker — this edit applies cleanly to the current `build.yml` and carries into the reusable-workflow refactor when p9 lands.
- **Out of scope** (deferred to follow-up changes — see §Future Work):
  - Moving `scan_image` off the PR gating path (`workflow_run` trigger).
  - Restricting scan to PRs that change `android.Dockerfile` or `config/version.json`.

## Future Work

These were investigated in the same research pass and intentionally deferred so each lands as its own reviewable change:

1. **Move Scout off the PR gating path.** Trigger `scan_image` via `workflow_run: build.yml` instead of `needs: build_image`. PR merges as soon as `build_image` + `test_image` are green; Scout comment posts asynchronously. Removes Scout entirely from the gating wall-clock.
2. **Conditional scan on image-touching PRs only.** Add a `paths:` filter so `scan_image` runs only when `android.Dockerfile`, `config/version.json`, `config/flutter_version.json`, or `script/setEnvironmentVariables.js` changes. Most PRs in this repo touch docs/CI/openspec and produce a bit-identical image. Scout already deduplicates per digest server-side, but the runner still spins up.
3. **Retire the orphaned Scout `prod` env stream.** Dashboard cleanup; not a workflow change.

Sources (researched during this change):

- [Docker Scout image analysis — SBOM attestation behavior](https://docs.docker.com/scout/explore/analysis/)
- [Docker Scout integrations overview (registry list)](https://docs.docker.com/scout/integrations/)
- [Docker Scout + GHA canonical example](https://docs.docker.com/scout/integrations/ci/gha/)
- [Scout compare CLI reference (`--to` flag)](https://github.com/docker/scout-cli/blob/main/docs/scout_compare.md)
- [DSOS program docs (per-Docker-Hub-repo Scout entitlement)](https://docs.docker.com/docker-hub/repos/manage/trusted-content/dsos-program/)
- [docker/scout-action README (action inputs)](https://github.com/docker/scout-action)
- [docker/hub-feedback#2445 — OAT cannot use `/v2/users/login/`](https://github.com/docker/hub-feedback/issues/2445)
- [docker/build-push-action attestation inputs](https://github.com/docker/build-push-action#inputs)
