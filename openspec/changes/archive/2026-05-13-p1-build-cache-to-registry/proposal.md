## Why

`build.yml/test_image` builds a multi-GB three-stage Docker image (`flutter` → `fastlane` → `android`) and uses `cache-from/to: type=gha,mode=max` (build.yml:89-90). The GitHub Actions cache backend has a 10 GB per-repository quota with LRU eviction, and this image's `mode=max` cache routinely exceeds that — so on long-tail branches (or after another workflow churns the cache) builds fall back to cold and the step runs ~6 min instead of ~2½ min.

Docker's own CI guide recommends `type=registry` for images that don't fit comfortably in the GHA quota ([source](https://docs.docker.com/build/ci/github-actions/cache/)). With GHCR available (the repo already pushes release images there), the registry cache is free, has no GitHub-side eviction, and is shared across branches.

This change replaces the GHA cache backend with a GHCR registry cache and removes the eviction-induced cold-build tail.

## What Changes

- `build.yml/test_image` `cache-from` → `type=registry,ref=ghcr.io/${{ github.repository_owner }}/flutter-android:buildcache`.
- `build.yml/test_image` `cache-to` → `type=registry,ref=ghcr.io/${{ github.repository_owner }}/flutter-android:buildcache,mode=max` — only on non-fork PRs and `workflow_dispatch` (fork PRs lack `packages: write`, so they fall back to `cache-from` only and skip `cache-to`).
- Add `packages: write` to the `test_image` job permissions (already present for Scout's PR comment) — confirms scope.
- Add GHCR login step alongside the existing Docker Hub login: `docker/login-action` with `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`.
- No change to `windows.yml` (separate image, separate concern — re-evaluate after this change lands).

## Capabilities

### New Capabilities

- `ci-image-build-cache`: defines how the Flutter Docker image build SHALL persist and reuse layer cache across CI runs — backend, eviction behavior, fork-PR fallback, and the cache-ref naming contract.

### Modified Capabilities

_None._

## Impact

- **Affected files**: `.github/workflows/build.yml:84-100` (the `Build image and push to local Docker daemon` step + new login step).
- **Behavioral change**: cache hits become stable across branches and over time; `build` step median wall-clock drops from ~2m23s (current cache-hit case) to ~50s once the registry cache is warm. Cold builds (first run after this change merges) take the full ~6 min and prime the cache.
- **GHCR storage**: `mode=max` registry cache for this image is ~3-5 GB and is overwritten in place on every push to the same tag (no growth). GHCR storage for public repos is free.
- **Risk**: a corrupted cache push could fail subsequent builds. Mitigation: `cache-to` runs after the build succeeds; if the push itself fails, the build still passes (buildx treats cache export as best-effort).
- **Out of scope**: changing the build itself, splitting Dockerfile stages into separately-cached images, caching on Windows runner.
- **Relevance gate**: a CI engineer noticing the `Build image` step is consistently ~1 min would see the spec captures the contract (registry cache, branch-shared, fork-PR fallback) rather than re-discovering the rationale from a blog post.
