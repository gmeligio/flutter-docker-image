# Proposal

## Why

Specs drift from the workflows and nothing catches it:

- `ci-parallel-image-validation` no longer matches `.github/workflows/build.yml` (#597): no `## Purpose`, pre-#477 job keys, a single-image model, and a finished one-time migration. Only one of its four requirements is unique; the rest duplicate `ci-image-handoff` and `ci-image-vulnerability-scan`. `ci-image-handoff` and `ci-image-build-cache` drifted the same way.
- Four more specs lack `## Purpose`, so `openspec validate --specs` fails (#561).
- No CI job runs `openspec validate` (#598).
- `openspec/config.yaml` spec rules target a "desktop user", which let a one-time migration requirement pass review (#599).

See `research.md`.

Relevance gate: the maintainer reads these specs to know what the PR checks page shows (`Build and push image (<name>)`, `Test image (<name>)`, `Scan image (<name>)`), which checks a fork contributor sees, and whether a spec edit is valid before merge. The maintainer's spec workflow is in scope: `config.yaml` `context:` is widened to say so (design D7), in this same change, so `ci-spec-validation` passes the gate it is reviewed under.

## What Changes

- **BREAKING (specs only)**: remove capability `ci-parallel-image-validation`. Its unique rule and rebuild ban move to `ci-image-handoff` (replacing the web-only copy in `web-image-testing`); its fork gate moves to `ci-image-vulnerability-scan`; its migration requirement is dropped.
- `ci-image-handoff`: describe the real handoff (`tag`, `is_fork`, `flutter_version` outputs; per-image artifact `image-<run_id>-<name>`); add "consumers never rebuild" and "test and scan validate each image in parallel after build", named by check display name.
- `ci-image-vulnerability-scan`: add the job-level fork gate as its own requirement.
- `ci-image-build-cache`: per-image `ghcr.io/<owner>/<image>:buildcache`; build job is `build-image`.
- Add `## Purpose` to `ci-image-handoff` (refreshed), `ci-image-anonymous-availability`, `generated-docs-and-examples`, `repository-wiki`, `windows-version-tracking`.
- New `mise run specs` task and `Validate specs` CI check on PRs touching `openspec/**`.
- `openspec/config.yaml` spec rules target the CI engineer or maintainer and reject one-time migration requirements.
- `build.yml:189` comment stops naming the removed spec. No image-pipeline behavior changes.

## Capabilities

### New Capabilities

- `ci-spec-validation`: `mise run specs` and the `Validate specs` PR check.

### Modified Capabilities

- `ci-image-handoff`: handoff outputs and artifact name match `build.yml`; adds no-rebuild and parallel per-image validation requirements.
- `ci-image-vulnerability-scan`: adds the job-level fork-PR gate on `scan-image`.
- `ci-image-build-cache`: cache tag is per image; scenarios reference `build-image`.
- `web-image-testing`: removes "Web image consumer jobs do not rebuild the image", now covered for every image by `ci-image-handoff` and `ci-image-vulnerability-scan`.
- `ci-parallel-image-validation`: deleted outright (no delta; see design.md D1).

## Impact

- `openspec/specs/`: 4 specs modified by delta, 1 new, 5 get a Purpose edit, `ci-parallel-image-validation/` deleted.
- `openspec/config.yaml`: `context:` widened, `rules.specs` reworded.
- `mise.toml`: new `specs` task. New `.github/workflows/openspec.yml`.
- `.github/workflows/build.yml:189` comment only.
- Closes #597, #561, #598, #599.
