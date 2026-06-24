## Why

When a CI engineer browses Docker Hub, each `flutter-*` repository's short description and Overview is how they tell — at a glance — which platform an image targets. Today that signal is broken: the `update-description` job (`release.yml:182-225`) only covers `flutter-android` and `flutter-web`, so **`flutter-windows` has no Overview at all**, and it pushes the single generic repository "About" blurb (`github.event.repository.description`) as the short description to *both* android and web — so neither names its platform. The short descriptions are also not durable: a manual per-platform edit is overwritten by the generic blurb on the next release.

This needs a spec because it changes user-observable registry metadata — what a CI engineer reads on Docker Hub before pulling — for every published image, and the behavior isn't owned by any existing capability (`web-image-release` mentions it in passing; `flutter-windows` has no requirement at all).

## What Changes

- Extend the `update-description` matrix in `release.yml` to cover **all three** published images — `flutter-android`, `flutter-web`, `flutter-windows` — so every Docker Hub repository gets its Overview synced (today `flutter-windows` gets none).
- Replace the generic `github.event.repository.description` short description with a **per-platform** short string carried inline on each matrix entry, so each repository states its platform and the value is version-controlled (durable across releases), not a manual edit the job overwrites.
- Keep the **same shared Overview** (`readme.md`) for all three repositories for now.
- The per-platform short descriptions (content-based, ≤100 bytes):
  - `flutter-android`: `Flutter with Android SDK & Fastlane for CI`
  - `flutter-web`: `Flutter with precached web engine for CI`
  - `flutter-windows`: `Flutter with VS Build Tools for CI`

No new credential: the existing `DOCKER_HUB_USERNAME` / `DOCKER_HUB_TOKEN` already drive the android/web sync.

## Capabilities

### New Capabilities

- `dockerhub-repository-description`: On tag-push release, every published image's Docker Hub repository description is synced — a shared Overview from `readme.md` and a durable, per-platform short description — for `flutter-android`, `flutter-web`, and `flutter-windows`.

### Modified Capabilities

- `web-image-release`: its "same metadata conventions" requirement drops the now-redundant "Docker Hub repository description … synced from `readme.md`" clause, which moves to (and is generalized by) the new `dockerhub-repository-description` capability. The OCI-label conventions are unchanged.

## Impact

- **CI**: `.github/workflows/release.yml` — the `update-description` job gains `flutter-windows` as a third matrix entry and a per-entry `short:` field; `short-description:` reads `${{ matrix.short }}` instead of `github.event.repository.description`. `needs: release-linux` and `if: github.event_name == 'push' && !cancelled()` are unchanged, so the Windows-only `workflow_dispatch` rebuild still skips description sync, and the existing Docker Hub credential is reused.
- **Registries**: the `flutter-windows` Docker Hub repository (published since 3.44.1) gains an Overview + short description; `flutter-android` / `flutter-web` short descriptions become platform-specific.
- **Overview source**: unchanged — `readme.md`, generated from `docs/src` via the existing MDX→MD pipeline (`repository-wiki`).
- **Not in scope**: Docker Scout coverage for `flutter-windows` (the `record-image` job has the same matrix omission — tracked in [issue #506](https://github.com/gmeligio/flutter-docker-image/issues/506)); per-platform Overviews (`docs/windows.mdx`/`docs/windows.md` exist for a future change); Quay and GHCR descriptions (Quay stays manual; GHCR has no write API and is OCI-label / linked-README driven); the broader `config/images.json` manifest and matrix de-duplication.
