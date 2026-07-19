# Contributing

## Repository wiki

An AI-generated wiki for this repository is available at [deepwiki.com/gmeligio/flutter-docker-image](https://deepwiki.com/gmeligio/flutter-docker-image). It covers architecture, Dockerfile stages, the CI/release pipeline, and more.

The wiki is kept current automatically: DeepWiki re-indexes the repository whenever it detects the DeepWiki badge in `readme.md`. No manual action is required after merging to `main`.

## Building the docs locally

`readme.md` and the per-backend CI examples under `examples/` are code-generated from `config/version.json` (the single source of truth). Do **not** edit those files by hand — edit the generators and regenerate:

- `readme.md` — composed by `docs/build.mjs` (Node standard library only, no dependencies). The same file serves as the GitHub README and the Docker Hub description.
- `examples/{github-actions,gitlab-ci,gitea-actions,forgejo-actions}.yml` — emitted from `docs/examples.cue` via `cue export`.
- `config/version.json` — the version values (Flutter, Fastlane, Gradle, NDK, build-tools, platforms) and the image tag injected into both.

`docs/contributing.md`, `docs/faq.md`, `docs/windows.md`, and `LICENSE.md` are static Markdown — edit them directly.

Regenerate everything with one task (`node` and `cue` are pinned in `mise.toml`):

```bash
mise run docs
```

CI enforces this: `update-docs.yml` re-runs `mise run docs` and fails with `git diff --exit-code` if the committed `readme.md` or `examples/` drift from the generators. On same-repo PRs the regenerated output is committed back automatically; fork PRs must run `mise run docs` and commit the result.

## Building the images locally

The versions below are illustrative — the authoritative values live in `config/version.json` (validated by `config/schema.cue`).

`android.Dockerfile` expects a few build arguments:

- `flutter_version <string>`: the Flutter version to build. Example: `3.44.6`
- `android_build_tools_version <string>`: the Android SDK Build Tools version. Example: `36.0.0`
- `android_platform_versions <list>`: the Android SDK Platforms to install, space-separated. Example: `36`

```bash
# Android
docker build --target android --build-arg flutter_version=3.44.6 --build-arg fastlane_version=2.237.0 --build-arg android_build_tools_version=36.0.0 --build-arg android_platform_versions="36" -t flutter-android:local -f android.Dockerfile .
```

`windows.Dockerfile` builds a Windows container (requires a Windows host with Docker in Windows-container mode) and expects:

- `flutter_version <string>`: the Flutter version to build. Example: `3.44.6`
- `git_version <string>`, `vs_cmake_version`, `vs_win11sdk_build`, `vs_vctools_version`: the Windows toolchain versions pinned under the `windows` block in `config/version.json`.

```powershell
# Windows (run on a Windows host in Windows-container mode)
docker build --target flutter --build-arg flutter_version=3.44.6 -t flutter-windows:local -f windows.Dockerfile .
```

## Editing GitHub Actions workflows

GitHub Actions versions are tracked with [gx](https://github.com/gmeligio/gx). The manifest at `.github/gx.toml` is the source of truth for version constraints, and `.github/gx.lock` records the resolved SHAs. Workflows must use SHA pins with a `# vX.Y.Z` comment.

When editing any file under `.github/workflows/` or `.github/actions/`:

1. Install `gx` locally: `brew install gmeligio/tap/gx`, `cargo install gx`, or grab a binary from [the GitHub Releases page](https://github.com/gmeligio/gx/releases).
2. Make your workflow edits.
3. Run `gx tidy` to sync `.github/gx.toml`, `.github/gx.lock`, and the workflow `uses:` lines.
4. Commit all three together (`.github/workflows/...`, `.github/gx.toml`, `.github/gx.lock`).

Adding a new action looks like adding a single line under `[actions]` in `.github/gx.toml`:

```toml
"some-org/some-action" = "^1"

```

…then `gx tidy` resolves the SHA, writes the lock entry, and rewrites the `uses:` line.

The `lint` job in `.github/workflows/gx.yml` fails any pull request that introduces an unpinned `uses:` reference or a lock that disagrees with the workflows. The sibling `tidy` job runs `gx tidy` and pushes a fixup commit on PRs from this repository if the lock is stale (forks must run `gx tidy` locally).

### Workflow security rules

Every workflow MUST satisfy:

1. **No `pull_request_target`.** It runs in the base repo's context with secrets; combined with `actions/checkout` of PR HEAD it is the "pwn request" attack class. The safe default is `on: pull_request`. Adding `pull_request_target` requires an OpenSpec proposal documenting the threat model.
2. **SHA-pinned actions** with a `# vX.Y.Z` comment. Enforced by `gx lint`.
3. **GitHub App tokens, not PATs**, for cross-repo writes (use the `VERIFIED_COMMIT_*` secrets via `actions/create-github-app-token`).
4. **`step-security/harden-runner` first step of every Linux job**, `egress-policy: audit`. Windows jobs are exempt — harden-runner does not support `windows-2025`.
5. **Top-level `permissions: contents: read`**, with broader scopes declared at the job that needs them.
6. **Top-level `concurrency:` on push-triggered shared-state workflows** — `cancel-in-progress: false` for release-path, `true` for CI.

The authoritative source is [openspec/specs/ci-workflow-hardening/spec.md](https://github.com/gmeligio/flutter-docker-image/blob/main/openspec/specs/ci-workflow-hardening/spec.md).

## Adding new Github Actions

When adding new Github Actions the `.github\renovate.json` needs to be checked and add the new action to:

* the automerge array if it's not an important action

### Dockerfile stages

1. `flutter` stage has only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
2. `fastlane` stage installs Ruby and the build tools fastlane needs, then installs the fastlane gem.
3. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.