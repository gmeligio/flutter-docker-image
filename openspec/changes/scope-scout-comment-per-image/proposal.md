# Proposal

## Why

Matrix legs of `scan-image` overwrite each other's Docker Scout PR comment ([#560](https://github.com/gmeligio/flutter-docker-image/issues/560)). `docker/scout-action` keys its comment on `(command, workflow name)`, so every image's leg upserts the same comment and the slowest leg (flutter-android) wins. On #558 flutter-web's +1 medium vulnerability vanished from the PR. All three scanned images now have baselines, so every PR collides three ways. The marker is hardcoded in Scout's closed binary; [docker/scout-action#52](https://github.com/docker/scout-action/issues/52) is open since 2024 with no fix through v1.29.0.

Spec relevance: the maintainer reviewing a PR loses a scanned image's vulnerability delta, which changes the observable output of `ci-image-vulnerability-scan`.

## What Changes

- Scout stops writing PR comments (`write-comment: false`); its job summary stays.
- Each `scan-image` leg posts its own report as a PR comment, created on first run and updated in place on later runs, identified by an image-scoped marker.
- The comment logic lives in a standalone TypeScript file under `script/`, run by `actions/github-script`.
- `scan-image` checks out the repository so it can load that file.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ci-image-vulnerability-scan`: adds the requirement that each scanned image owns exactly one PR comment carrying its own Scout compare report.

## Impact

- `.github/workflows/build.yml` (`scan-image` job): checkout step, `write-comment: false`, new comment step.
- New `script/commentScoutReport.ts`.
- No new third-party action; `actions/github-script` and `actions/checkout` are already pinned in this repo.
- Open PRs keep their old Scout comment (old marker) as stale history.
