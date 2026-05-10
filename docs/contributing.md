<!--- This markdown file was auto-generated from "contributing.mdx" -->

# Contributing

## Repository wiki

An AI-generated wiki for this repository is available at [deepwiki.com/gmeligio/flutter-docker-image](https://deepwiki.com/gmeligio/flutter-docker-image). It covers architecture, Dockerfile stages, the CI/release pipeline, and more.

The wiki is kept current automatically: DeepWiki re-indexes the repository whenever it detects the DeepWiki badge in `readme.md`. No manual action is required after merging to `main`.

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

## Adding new Github Actions

When adding new Github Actions the `.github\renovate.json` needs to be checked and add the new action to:

* the automerge array if it's not an important action

### Dockerfile stages

1. `flutter` stage hast only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
2. `fastlane` stage has the dependencies required to install fastlane but doesn't install fastlane.
3. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.