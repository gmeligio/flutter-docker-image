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

**Decision**: Change the existing `docker/build-push-action` step from `load: true` to a multi-line `outputs:` that emits both a local docker image and a registry push:

```yaml
outputs: |
  type=docker,name=<local-tag>
  type=registry,push=true,name=ghcr.io/<owner>/flutter-android:<handoff-tag>
```

`load: true` and `push: true` are mutually exclusive shorthands for single-output `--output=type=docker` / `--output=type=registry` respectively, so the `outputs:` form is required when emitting both. Multi-output is a stable feature in buildx and BuildKit ≥ 0.13.0 (released Feb 2024) and is documented as first-class behavior. Order matters in one edge case (digest-pushed manifests, [discussion #1318](https://github.com/docker/build-push-action/discussions/1318)); place `type=docker` first to stay clear of it.

**Alternatives considered**:

- *Build with `push: true` only, then `docker pull` for the test step.* Rejected — adds a registry round-trip in the same job that already has the bits locally.
- *Two sequential `build-push-action` invocations* (first `load: true`, second `push: true`), both backed by the registry cache from p1. The second is a near-full cache hit (~5-10s of buildkit overhead). Marginally simpler YAML, marginally more wall-clock. Equally acceptable; pick if multi-output ever misbehaves for this image.
- *Build with `load: true`, then `docker tag` + `docker push` in a separate `run:` step.* Works but breaks the manifest-digest contract for any future multi-platform extension. Reject for that reason alone.

**Rationale**: One buildkit run emits both the local image (for the current serial test/scout) and the registry tag (for p3 consumers). Multi-output is no longer new (2+ years stable); the only nuance is exporter ordering.

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
- **R3**: Multi-output buildx is stable as of BuildKit 0.13.0 (Feb 2024) and is the documented way to combine `type=docker` and `type=registry`. Known edge case: ordering matters for digest-pushed manifests (place `type=docker` first). If multi-output ever misbehaves for this image, the documented fallback is two sequential build-push-action steps, accepting ~5-10s of buildkit overhead on the second (cached) run.
