## Why

CI engineers landing on the repo today only get a static README and two short markdown files. There is no way to ask "how does the windows pipeline cache the SDK?" or "what changed in the android Dockerfile recently?" without grepping the source. Hosted DeepWiki indexes any public GitHub repo for free, generates an architecture-aware wiki, and auto-refreshes when the repo carries a DeepWiki badge — so a one-time integration gives users a queryable, always-current doc surface at zero infra cost.

This passes the relevance gate: the badge and the linked wiki are visible to anyone reading the README, and the wiki itself is the experience the CI engineer notices when they click through.

## What Changes

- Add a DeepWiki badge to the README header so users can reach `deepwiki.com/gmeligio/flutter-docker-image` in one click. Source the badge in `docs/src/badges.mdx` so the existing MDX→MD compile carries it into `readme.md`.
- Add `.devin/wiki.json` with `repo_notes` describing the project shape (android vs windows split, MDX docs pipeline, OpenSpec workflow) and a curated `pages` outline so the auto-generated wiki reflects how the repo is actually organized.
- Document the integration in `docs/src/contributing.mdx` (recompiled into `docs/contributing.md`) so contributors know the wiki exists, how to refresh it, and how the badge wires up auto-refresh.
- No CI changes, no new dependencies in the Dockerfiles, no changes to image contents.

## Capabilities

### New Capabilities
- `repository-wiki`: An always-current, AI-generated knowledge base for the repository, reachable from the README via a badge and refreshed automatically when the repo changes.

### Modified Capabilities
<!-- None — existing specs (actions-version-tracking, flutter-version-update) are unrelated. -->

## Impact

- **Files added**: `.devin/wiki.json`
- **Files modified**: `docs/src/badges.mdx`, `docs/src/contributing.mdx`, regenerated `readme.md` and `docs/contributing.md` via `docs/src/compile.js`
- **External dependency**: Hosted DeepWiki service (`deepwiki.com`) — free for public repos, owned by Cognition AI. No code or secrets sent; DeepWiki reads the public repo directly.
- **No impact on**: Docker images, CI workflows, release pipeline, version bump scripts, end-user `docker run` UX.
