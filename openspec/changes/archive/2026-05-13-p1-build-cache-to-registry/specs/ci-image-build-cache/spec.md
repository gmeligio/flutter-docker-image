## ADDED Requirements

### Requirement: Build cache uses GHCR registry backend, not GHA cache

The Flutter Docker image build in `.github/workflows/build.yml` SHALL persist its layer cache to the GitHub Container Registry under a deterministic, branch-shared tag (`ghcr.io/<owner>/flutter-android:buildcache`) using `type=registry,mode=max`. The build SHALL NOT use `type=gha` for either `cache-from` or `cache-to`.

The experience context is the maintainer watching the `Build image` step on the PR check page — with `type=gha` and `mode=max`, eviction caused 20-30% of builds to fall back to cold (~6 min); with the registry backend, the cache is shared across branches and not subject to GHA's 10 GB quota.

#### Scenario: Non-fork PR populates the registry cache

- **GIVEN** a PR whose head branch lives in this repository (not a fork) and the `test_image` job runs
- **WHEN** the build completes successfully
- **THEN** the build pushes the cache manifest to `ghcr.io/<owner>/flutter-android:buildcache`
- **AND** the next run of the same workflow (any branch) imports from that manifest

#### Scenario: Subsequent non-fork run hits the registry cache

- **GIVEN** the `buildcache` tag already exists from a prior successful run
- **WHEN** a new `test_image` job runs
- **THEN** the `Build image` step log contains `importing cache manifest from ghcr.io/<owner>/flutter-android:buildcache`
- **AND** the `Build image` step completes in ≤ 90 seconds at the median across 10 consecutive cache-hit runs

### Requirement: Fork PRs read the registry cache but do not write to it

Fork PRs do not receive `packages: write` on the `GITHUB_TOKEN`, so `cache-to` SHALL be omitted for them. `cache-from` SHALL still reference the registry tag so fork builds get the warm-cache benefit, even though they cannot refresh the cache.

The experience context is a community contributor opening a PR from their fork — their build still benefits from the latest cache pushed by maintainer PRs, but they cannot pollute or invalidate the shared cache.

#### Scenario: Fork PR build reads but does not write the cache

- **GIVEN** a PR opened from a fork (`github.event.pull_request.head.repo.full_name != github.repository`)
- **WHEN** the `test_image` job runs
- **THEN** the `Build image` step uses `cache-from: type=registry,ref=ghcr.io/<owner>/flutter-android:buildcache` only
- **AND** no `cache-to` value is passed to `docker/build-push-action`
- **AND** the build succeeds even if the cache manifest is unavailable (cold-build fallback)

### Requirement: Registry cache tag does not grow unbounded

The cache tag `ghcr.io/<owner>/flutter-android:buildcache` SHALL be overwritten in place by `mode=max` exports — the manifest is replaced, not appended. The tag SHALL NOT grow more than 20% over its steady-state size across a rolling 7-day window of normal CI activity.

The experience context is the maintainer scanning GHCR storage costs (or quota usage on a private mirror) — `mode=max` is the cost-correct setting because it includes intermediate layers, but only as long as the manifest does not accumulate dead refs.

#### Scenario: Cache tag size after a week of normal CI

- **GIVEN** the `buildcache` tag has existed for ≥ 7 days under normal CI load (≥ 10 builds)
- **WHEN** the size is sampled
- **THEN** the size is within 20% of the size 7 days prior
- **AND** no manual cleanup of the tag is required
