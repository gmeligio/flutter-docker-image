## Context

`release.yml` publishes three images: `flutter-android` and `flutter-web` from `android.Dockerfile` via the `release-linux` matrix, and `flutter-windows` from `windows.Dockerfile` via the `release-windows` caller of the reusable `windows-image.yml`. A separate `update-description` job (`release.yml:182-225`) syncs Docker Hub metadata with `peter-evans/dockerhub-description@v5`, matrixed over `flutter-android` and `flutter-web` only, with `needs: release-linux` and `if: github.event_name == 'push' && !cancelled()`. It passes `short-description: github.event.repository.description` (the single repo "About" blurb) and `readme-filepath: readme.md`.

`readme.md` is a generated artifact (compiled from `docs/src/readme.mdx` by the MDX→MD pipeline governed by `repository-wiki`); it is a generic multi-image Overview. `peter-evans/dockerhub-description` updates an existing repo's short description (≤100 bytes) and full description (≤25,000 bytes); it requires the repo to already exist and a Docker Hub password or PAT with write + repo Admin.

Constraints: sole maintainer; descriptions are near-static; `flutter-windows` is built by a different path but its Docker Hub repo already exists (published since 3.44.1); the Windows-only `workflow_dispatch` recovery path (per `windows-image-release`) must keep skipping description sync.

## Goals / Non-Goals

**Goals:**
- Every published image's Docker Hub repo shows an Overview (today `flutter-windows` shows none).
- Each repo's short description names its platform and is durable across releases (not overwritten by the generic blurb).
- Keep one shared Overview (`readme.md`) for all three for now.
- Minimal surface: one matrix + one field, no new job, no new credential.

**Non-Goals:**
- Per-platform Overviews (deferred; `docs/windows.mdx` exists for later).
- Docker Scout coverage for `flutter-windows` ([issue #506](https://github.com/gmeligio/flutter-docker-image/issues/506)).
- Quay / GHCR description automation (Quay manual; GHCR has no write API).
- A `config/images.json` manifest / de-duplicating the image set across the other matrices (separate change).

## Decisions

### Decision 1: One unified `update-description` matrix over all three images
Add `flutter-windows` as a third entry to the existing `update-description` matrix, rather than a new description step inside `windows-image.yml`. Description sync is registry-uniform — it needs only the repo name, the Docker Hub credential, the readme, and the short string — so it does not matter that Windows is built by a different workflow. One job owns all description syncing.

- **Alternative rejected — describe Windows inside `windows-image.yml`:** that reusable workflow's job is *building*; adding "describe" there splits the logic across two files and drifts the per-platform strings.

### Decision 2: Per-platform short string inline on each matrix entry
Carry the short description as a `short:` field on each matrix `include` entry and pass `short-description: ${{ matrix.short }}`. The string is used in exactly one place (this job), so the matrix entry is its natural, lowest-friction home — version-controlled, reviewed, ≤100 bytes.

- **Why not `github.event.repository.description`:** it is a single generic blurb → identical, non-platform-specific short descriptions, and it overwrites any manual per-platform edit each release.
- **Why not a per-image file / `config/images.json`:** the manifest is a deferred, separate change; for one short string per image, an inline matrix field is simpler and migrates cleanly into the manifest later.

### Decision 3: Keep the shared `readme.md` Overview
All three repos get `readme-filepath: readme.md`. A per-platform Overview (`docs/windows.mdx` → `docs/windows.md`) is possible later but adds scope without a current need.

### Decision 4: Keep `needs: release-linux` and the `if: github.event_name == 'push'` guard
The job's `needs:` and `if:` are unchanged. Description sync is repo-level metadata, decoupled from any single run's image push: the three Docker Hub repos already exist, so the `flutter-windows` leg does not need to wait for `release-windows` (avoiding a ~30-minute wait behind the Windows build) and the sync still runs once per push after the Linux build.

- **Consequence for `workflow_dispatch`** (Windows-only rebuild, per `windows-image-release`): the retained `if: github.event_name == 'push'` keeps `update-description` skipped on dispatch — including the new Windows leg — so the recovery path is unchanged.
- **Edge case:** a brand-new platform's very first release would run the description leg before its repo exists (first push) → that leg errors (isolated by `fail-fast: false`, loud, recoverable). Not applicable to the three current images, which all exist.

## Automated Test Strategy

- This change has no unit-testable logic; verification is operational. The load-bearing assertion is "after a tag push, each of the three Docker Hub repos shows the shared Overview and its platform-specific short description."
- **Critical path:** a release run's `update-description` job succeeds for all three legs (`fail-fast: false`), and a check of the three Docker Hub repo pages shows the expected Overview + short string. Workflow YAML is gated on PR by `gx` / `actionlint`.
- **No new test infrastructure.** Docker Hub description state is not anonymously queryable the way image manifests are (`verify_published_image.sh` resolves manifests, not metadata), so there is no automated post-release assertion analogous to `verify-published`; the check is a one-time visual confirmation after the first release that carries this change.

## Observability

- **Failure is a named matrix leg:** a sync failure surfaces as `Update Docker Hub description (flutter-windows)` (etc.) on the release run; `fail-fast: false` keeps one image's failure from hiding another's, and the per-leg name says which image's sync failed.
- **No silent failure:** `peter-evans/dockerhub-description` exits non-zero (failing the leg) on an API error — e.g., a missing repo or an under-scoped token — so a misconfiguration is loud.
- **Partial-release resilience:** `if: !cancelled()` keeps description sync running even when a release leg failed, so a transient build failure does not silently skip metadata sync for the images that did publish.
