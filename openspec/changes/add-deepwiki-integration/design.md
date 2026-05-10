## Context

The repo's user-facing docs are limited to `readme.md` (compiled from `docs/src/readme.mdx` via `docs/src/compile.js`) plus `docs/contributing.md` and `docs/windows.md`. There is no architectural overview, no Q&A surface, and no auto-update story. Cognition AI's hosted DeepWiki indexes any public GitHub repo for free, generates an architecture-aware wiki with diagrams and a chat interface, and — when the repo carries a DeepWiki badge — re-indexes automatically as `main` evolves. The wiki is reached by replacing `github.com` with `deepwiki.com` in the repo URL.

This proposal opts the repo into that hosted service. It does not stand up a docs site, replace the existing MDX pipeline, or send any code to a third party that doesn't already read it from public GitHub.

## Goals / Non-Goals

**Goals:**
- Give README readers a one-click path to an AI-generated wiki for the repo.
- Steer the generated wiki's structure to match how this repo is actually organized (android vs windows image, MDX docs pipeline, OpenSpec workflow, release/CI pipeline) instead of accepting the default outline.
- Keep the wiki current without any maintainer action after merge.
- Keep the existing MDX→MD docs pipeline intact and authoritative for committed markdown.

**Non-Goals:**
- Self-hosting DeepWiki or any OSS variant (deepwiki-open, OpenDeepWiki, RepoWiki). The hosted free tier is sufficient for a public repo of this size.
- Replacing the MDX docs pipeline or migrating to Mintlify/Docusaurus/MkDocs.
- Wiring the DeepWiki MCP server into shared tooling. Individual contributors can register `https://mcp.deepwiki.com/mcp` in their own Claude Code config; that is out of scope for this repo change.
- Generating reference docs from Dockerfiles or scripts.
- Authoring wiki page bodies by hand. The whole point is that DeepWiki generates them.

## Decisions

### Use hosted DeepWiki, not a self-hosted alternative

DeepWiki hosted (`deepwiki.com`) is free for public repos, is already operating against this repo's public GitHub URL, and requires zero infra. Self-hosted alternatives (deepwiki-open, OpenDeepWiki, RepoWiki) would require provisioning a server, paying for LLM tokens, and maintaining another service — all to reproduce a free capability. The trade is vendor lock-in to Cognition AI's roadmap, which is acceptable because the integration surface is one badge URL and one JSON file that any replacement could read.

Source: <https://docs.devin.ai/work-with-devin/deepwiki>, <https://cognition.ai/blog/deepwiki>.

### Source the badge in `docs/src/badges.mdx`, not directly in `readme.md`

`readme.md` is auto-generated and carries the comment `<!--- This markdown file was auto-generated from "readme.mdx" -->`. Editing it directly would be undone by the next compile. The MDX source for the badge row already lives at `docs/src/badges.mdx`. Adding the DeepWiki badge there flows it into the recompiled README and keeps the existing pipeline as the single source of truth.

### Use `.devin/wiki.json` to steer page generation

DeepWiki's documented configuration file is `.devin/wiki.json`, which accepts a `repo_notes` array (steering context, ≤10k chars per note) and a `pages` array (explicit page outline with optional parent/child hierarchy). Without this file the wiki falls back to a generic auto-outline that wouldn't distinguish the android image, the windows image, the MDX docs pipeline, or the OpenSpec workflow. Authoring this file is the only way to make the wiki reflect the repo's actual axes of variation.

Source: <https://docs.devin.ai/work-with-devin/deepwiki>.

### Trust badge-presence as the auto-refresh trigger

DeepWiki refreshes wikis automatically for repos that carry a DeepWiki badge in their README. The repo already gets DeepWiki-generated content because it's public; the badge is what unlocks the auto-refresh path. No CI hook, no webhook, no scheduled workflow is needed.

Source: badge generator and behavior described at <https://deepwiki.ryoppippi.com/> and the DeepWiki dev guide.

### Use the standard Shields-style badge

The DeepWiki badge format used widely in the ecosystem is `https://deepwiki.com/badge.svg` linking to `https://deepwiki.com/<owner>/<repo>`. This matches the visual style of the other badges already in the README (OpenSSF Scorecard, channel, Docker version, Docker pulls) and avoids inventing a custom badge.

## Automated Test Strategy

This change has no runtime code path, so the verification surface is small and document-shaped. The critical path is: (1) the badge ends up in the regenerated `readme.md`, (2) the JSON config is parseable, (3) the contributing doc gains the new section.

- **Build verification**: run `docs/src/compile.js` (or the existing npm script) and confirm the regenerated `readme.md` contains the DeepWiki badge in the header row. This is the same pipeline contributors already use; no new infrastructure.
- **JSON validity**: `node -e "JSON.parse(require('fs').readFileSync('.devin/wiki.json','utf8'))"` — fast, no dependency.
- **Manual smoke check**: open `https://deepwiki.com/gmeligio/flutter-docker-image` after merge and confirm the configured `pages` outline shows up. This is the user-visible outcome and cannot be automated against a third-party service.
- **No new test infrastructure** is introduced. Adding a CI job to validate the JSON would be over-engineering for a single 30-line config; reviewers can read it.

## Observability

Failures are loud and shallow:
- A malformed `.devin/wiki.json` would surface as DeepWiki refusing to apply the configuration; the wiki would fall back to its default outline. Detection: open the wiki page after merge.
- A broken badge URL would render as a broken-image icon in `readme.md` — visible immediately on GitHub.
- A stale wiki (auto-refresh not firing) would surface to readers as out-of-date page content. Detection: spot-check after notable merges.

There is no silent-failure path that affects image users (the Docker images themselves are untouched). No new logs, metrics, or alerts are warranted.

## Risks / Trade-offs

- **[Vendor dependency on Cognition AI]** → Mitigation: integration surface is one badge URL + one JSON file. If Cognition discontinues the free tier we can either remove the badge (no functional regression beyond the wiki page itself) or point the same `.devin/wiki.json` at a self-hosted deepwiki-open deployment, which reads the same shape.
- **[Generated content quality is outside maintainer control]** → Mitigation: `repo_notes` and the `pages` outline give substantial steering; if a page is wrong, edit the notes rather than the page. Wiki is supplementary to the README, not load-bearing for image users.
- **[Auto-refresh cadence is undocumented]** → Mitigation: stale-by-a-few-hours is acceptable for a docs surface; no SLA is being promised to readers.
- **[`.devin/` directory may surprise contributors]** → Mitigation: contributing.md gains a section explaining what the file is for.

## Migration Plan

Single-PR rollout, no data migration:
1. Add the badge to `docs/src/badges.mdx` and recompile docs.
2. Add `.devin/wiki.json` with curated `repo_notes` and `pages`.
3. Add the contributing section.
4. Merge.
5. Within DeepWiki's refresh window, the wiki at `deepwiki.com/gmeligio/flutter-docker-image` reflects the new outline.

Rollback: revert the PR. The wiki itself remains accessible (DeepWiki indexes public repos regardless), but auto-refresh stops and the badge disappears from the README. No image, CI, or release impact.

## Open Questions

None blocking. The DeepWiki refresh cadence is not publicly documented as a hard SLA, but that is an acceptable unknown for a supplementary docs surface.
