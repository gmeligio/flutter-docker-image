## Why

CI run [26333167642](https://github.com/gmeligio/flutter-docker-image/actions/runs/26333167642/job/77522482488) failed at the `Setup CUE` step with `401 Bad credentials` from `jaxxstorm/action-install-gh-release` calling `GET /repos/cue-lang/cue/releases/tags/v0.15.0`. The repository already declares `cue = "0.15.0"` in `mise.toml`, but no workflow actually consumes that manifest — every job re-installs CUE via a third-party action with version, tag, and SHA256 digest duplicated **9 times** across 3 workflows. The Node toolchain has the same duplication shape (`actions/setup-node` in 3 jobs). Switching to `jdx/mise-action@v4` collapses both into a single step that reads `mise.toml`, eliminating the duplication and incidentally fixing the 401 by relying on the action's well-tested `${{ github.token }}` default.

## What Changes

- Add `node = "lts"`, `git-cliff = "2.10.1"`, and `"github:gmeligio/gx" = "0.7.1"` to `mise.toml` (CUE pin already present).
- Replace every `Setup CUE` step (9 occurrences in `ci.yml`, `build.yml`, `update_version.yml`) with `uses: jdx/mise-action@v4`.
- Replace every `Setup NodeJS` step (3 occurrences in `build.yml`, `update_docs.yml`, `update_version.yml`) with `uses: jdx/mise-action@v4`. The previous `cache: npm` behavior is **intentionally dropped** for now — `npm ci` will run cold in the docs jobs.
- Replace both `Install gx` steps in `.github/workflows/gx.yml` (the `lint` and `tidy` jobs) with `uses: jdx/mise-action@v4`, sourcing `gx` v0.7.1 from `mise.toml` via the `github:` backend.
- Replace both `Setup git-cliff` steps (in `changelog.yml` and `release.yml`) with `uses: jdx/mise-action@v4`, sourcing `git-cliff` 2.10.1 from `mise.toml` via the registry alias.
- Add `jdx/mise-action = "^4"` to `.github/gx.toml` (and the corresponding `.github/gx.lock` entry).
- **REMOVE** `jaxxstorm/action-install-gh-release` and `actions/setup-node` from `.github/gx.toml` (no workflow references them after this change), and prune their `.github/gx.lock` entries on the same PR (required by the `actions-version-tracking` spec's "mutually consistent on merge" invariant).

## Capabilities

### New Capabilities

- `ci-runtime-tool-versioning`: establishes `mise.toml` as the single source of truth for CI runtime tool versions (initially `cue`, `node`, `gx`, and `git-cliff`), consumed by every workflow via `jdx/mise-action@v4`. The capability covers: where versions live, how they reach `$PATH` in each job, and the invariant that no workflow may install these tools by any other mechanism. A CI engineer looking up "what version of cue does CI use?" SHALL find a single, authoritative answer in `mise.toml`.

### Modified Capabilities

None at the requirement level. The `actions-version-tracking` spec already governs the invariant that `.github/gx.toml`, `.github/gx.lock`, and workflow `uses:` SHAs stay mutually consistent. This change exercises that requirement (adding `jdx/mise-action`, removing `jaxxstorm/action-install-gh-release` and `actions/setup-node`) but does not modify the requirement itself. The implementation plan in `tasks.md` enforces the invariant by treating manifest, lockfile, and workflow edits as a single atomic PR.

## Impact

- **Workflows**: `.github/workflows/ci.yml`, `.github/workflows/build.yml`, `.github/workflows/update_version.yml`, `.github/workflows/update_docs.yml`, `.github/workflows/gx.yml`, `.github/workflows/changelog.yml`, `.github/workflows/release.yml`.
- **Manifests**: `mise.toml` (gains `node = "lts"`, `git-cliff = "2.10.1"`, and `"github:gmeligio/gx" = "0.7.1"`), `.github/gx.toml`, `.github/gx.lock`.
- **Runtime behavior**: `cue`, `node`, `gx`, and `git-cliff` continue to be on `$PATH` inside each job that needs them. Tool versions are now sourced from `mise.toml`.
- **Performance**: docs jobs lose npm package caching; expect a one-time `npm ci` cold cost (~10–20 s) per affected run until caching is re-introduced in a follow-up.
- **Dependencies dropped**: `jaxxstorm/action-install-gh-release`, `actions/setup-node`.
- **Dependency added**: `jdx/mise-action@v4`.
- **Chicken-and-egg note**: `.github/workflows/gx.yml` itself runs `gx lint`/`gx tidy`. After this change, that workflow bootstraps `gx` via `jdx/mise-action` — which is itself an entry in `.github/gx.toml`. This is fine (the action is pinned by SHA via the standard checkout-time state), but worth knowing: if `mise-action` is ever yanked, `gx tidy` cannot auto-recover the lockfile.
- **No image / runtime impact** on published `flutter-android` (and Windows) images — this is a CI infrastructure refactor.
