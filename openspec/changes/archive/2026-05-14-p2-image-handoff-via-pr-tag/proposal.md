## Why

Today `test_image` builds the image with `load: true` (build.yml:88) into the local Docker daemon, then both `Test image` (container-structure-test) and `Scan with Docker Scout` consume that local image serially in the same job. There is no way for a downstream job to consume the freshly-built image without rebuilding it — the local daemon is per-runner-VM, and the build artifact is multi-GB.

This blocks **p3** (parallelize validation): to fan-out test + scan into separate jobs, those jobs need a shared place to pull the image from. This change introduces that handoff mechanism without yet reorganizing the jobs — it adds a push of the just-built image to a temporary GHCR tag (`pr-<number>` / `branch-<branch>` for `workflow_dispatch`), and exposes the tag as a job output. Fork PRs that cannot push to GHCR fall back to `actions/upload-artifact` with a `docker save` tarball.

This is intentionally a **no-behavior-change-yet** step: the existing `Test image` and `Scan with Docker Scout` steps still consume the locally-loaded image. Only after p3 lands do downstream jobs start pulling the handoff tag.

## What Changes

- In `build.yml/test_image`, after the existing `docker/build-push-action` step (which keeps `load: true`), add a second `docker/build-push-action` step (or change the existing one to `outputs: type=image,push=true` and let buildx tee both load + push from the same buildkit run) that pushes the image to `ghcr.io/${{ github.repository_owner }}/flutter-android:pr-${{ github.event.pull_request.number || github.run_id }}` — gated to non-fork PRs and `workflow_dispatch`.
- For fork PRs, add a fallback step: `docker save ${{ image_tag }} | gzip > image.tar.gz` and `actions/upload-artifact` with `name: image-${{ github.run_id }}`, `retention-days: 1`. Fork-PR p3 jobs will `download-artifact` + `docker load`.
- Expose two job outputs on `test_image` (which p3 will rename to `build_image`):
  - `image_ref`: the full registry ref (`ghcr.io/.../flutter-android:pr-N`) on non-fork; empty string on fork.
  - `image_artifact`: artifact name on fork; empty on non-fork.
- Document the tag format in the spec so p4 (cleanup) and p3 (consumers) can rely on it.
- This change does **not** yet remove the serial `Test image` and `Scan with Docker Scout` steps — those stay until p3.

## Capabilities

### New Capabilities

- `ci-image-handoff`: defines the contract by which a CI job that builds the Flutter Docker image makes that image available to other jobs in the same run — registry-tag handoff for non-fork PRs, artifact handoff for fork PRs, and the naming and output schema both paths SHALL satisfy.

### Modified Capabilities

_None._

## Impact

- **Affected files**: `.github/workflows/build.yml:84-101` (the build step + new push/save step + outputs block on the job).
- **Behavioral change**: the build now also produces a registry tag (non-fork) or artifact (fork). No effect on `Test image` or `Scout` until p3.
- **GHCR storage**: each PR creates a temporary tag; p4 will clean these up on PR close. Until p4 lands, expect tags to accumulate at the rate of new PRs.
- **Fork-PR slowdown**: the `docker save | gzip` + upload is ~1-2 min for a 5 GB image. This regresses fork-PR wall-clock by that amount, but only until p3 redeems the cost via parallelization.
- **Risk**: a build that succeeds but fails the push leaves the job in an ambiguous state. Mitigation: the push uses `if: success()` and the job fails on push failure (do not `continue-on-error: true` — silently losing the handoff would break p3 consumers later).
- **Depends on**: p1 (registry login is shared infra) — if p1 has not landed, this change adds its own `Login to GHCR` step.
- **Out of scope**: cleaning up the tags (p4), consuming the tags (p3), Windows image handoff.
