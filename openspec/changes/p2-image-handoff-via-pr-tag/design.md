## Context

The build today produces a local image (`load: true`) on the runner VM. To split testing and scanning into parallel jobs (p3), those jobs need a way to consume the same image bits without rebuilding. Three handoff mechanisms exist on GitHub-hosted runners:

1. **Registry push** — push to a tag the next job pulls. Standard, fast, but requires `packages: write` which fork PRs lack.
2. **Artifact upload** — `docker save | gzip` → `upload-artifact` → `download-artifact` → `docker load`. Works for fork PRs but is slow for multi-GB images (~1-2 min upload + ~1-2 min download).
3. **Self-hosted runner with shared storage** — out of scope; this repo uses GitHub-hosted runners.

Only (1) and (2) are viable. The contract has to handle both because the repo accepts fork PRs.

## Goals / Non-Goals

**Goals:**

- A single, named handoff contract that downstream jobs (p3 test + scan) consume via job outputs.
- Non-fork PRs use the fast path (registry); fork PRs use the artifact path automatically.
- The handoff is idempotent: a re-run of the same PR overwrites the same `pr-N` tag (no garbage from re-runs).
- Tag format is documented and stable so p4 can rely on it for cleanup.

**Non-Goals:**

- Reorganizing the jobs (that's p3).
- Optimizing the artifact path beyond `gzip` (~2 min handoff is acceptable for the fork-PR minority).
- Cleaning up the tags (that's p4).

## Decisions

### D1. Push and load from the same buildx run

**Decision**: Change the existing `docker/build-push-action` step from `load: true` to `outputs: type=image,push=true,name=ghcr.io/<owner>/flutter-android:pr-N` + `load: true` (buildx supports multi-output in one invocation when using the docker-container driver). If buildkit's multi-output gives trouble, fall back to two sequential `build-push-action` invocations both backed by the cache from p1 — the second is near-instant.

**Alternatives considered**:

- *Build with `push: true` only, then `docker pull` for the test step.* Rejected — adds a registry round-trip in the same job that already has the bits locally.
- *Build with `load: true`, then `docker tag` + `docker push` in a separate step.* Works, simpler to read, but does two cache materializations. Acceptable fallback if multi-output is flaky.

**Rationale**: The cheapest is one buildkit run that emits both a local image (for the current serial test/scout) and a registry tag (for p3 consumers).

### D2. Tag format: `pr-<number>` for PRs, `branch-<branch>` for `workflow_dispatch`

**Decision**: Tag = `pr-${{ github.event.pull_request.number }}` for `pull_request` events, `branch-${{ github.ref_name }}` for `workflow_dispatch`. Slashes in branch names are replaced with `-`.

**Alternatives considered**:

- *Use `github.run_id`.* Rejected — a new tag per re-run accumulates garbage that p4 has to chase down. PR number is stable across re-runs.
- *Use `github.sha`.* Rejected for the same reason; a force-push generates a new tag.

**Rationale**: Stable per-PR tag means re-runs overwrite in place. p4's cleanup logic becomes "on PR close, delete `pr-<number>`" — a single-tag delete, no scanning required.

### D3. Fork PRs use `actions/upload-artifact` with gzipped `docker save`

**Decision**: When `github.event.pull_request.head.repo.full_name != github.repository`, skip the push and instead run `docker save <tag> | gzip > image.tar.gz` (≈ 5 GB → ~2 GB compressed for this image), then `actions/upload-artifact@v5` with `retention-days: 1` and a deterministic name `image-${{ github.run_id }}`.

**Alternatives considered**:

- *Refuse to handoff for fork PRs, run test+scout serially as today.* Rejected — fork PRs would lose the parallelization benefit from p3, which is exactly the slow case where contributors most want fast feedback.
- *Use `docker save` without gzip.* Rejected — uncompressed save is ~5 GB, the upload is bandwidth-bound, and `gzip -1` saves ~50% in ~30s.
- *Use `zstd`.* Slightly faster than gzip but the consumer (`docker load`) needs `zstd` installed; gzip is universal.

**Rationale**: 2 minutes of fork-PR slowdown is an acceptable price for the parallelization win in p3. The deterministic artifact name lets p3 download by name without scanning the artifact list.

### D4. Outputs schema: `image_ref` and `image_artifact`

**Decision**: The build job exposes two outputs:

- `image_ref`: full registry ref on non-fork; empty string on fork.
- `image_artifact`: artifact name on fork; empty string on non-fork.

Consumers (p3) branch on which is non-empty.

**Alternatives considered**:

- *A single output `image` plus a `handoff_kind` discriminator (`"registry" | "artifact"`).* Equivalent. The two-output form is slightly more explicit in YAML and saves one `if` branch in the consumer.

**Rationale**: A consumer that misses the fork case fails at the `pull`/`download` step with a typed error, not silently runs on yesterday's image.

## Risks / Trade-offs

- **R1**: GHCR rate-limiting on the push. Unlikely at this volume but documented as a future watch-item.
- **R2**: Artifact storage cost for fork PRs. Retention 1 day caps total storage at ~2 GB × (active fork PRs in the last 24 h), well within free-tier limits for a public repo.
- **R3**: Multi-output buildx mode is newer; if it misbehaves we fall back to a sequential build + push, accepting a ~10s rebuild on top of the cache.
