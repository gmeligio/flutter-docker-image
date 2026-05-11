## Context

The repo's user-facing docs are limited to `readme.md` (compiled from `docs/src/readme.mdx` via `docs/src/compile.js`) plus `docs/contributing.md` and `docs/windows.md`. There is no architectural overview, no Q&A surface, and no auto-update story. Cognition AI's hosted DeepWiki indexes any public GitHub repo for free, generates an architecture-aware wiki with diagrams and a chat interface, and — when the repo carries a DeepWiki badge — re-indexes automatically as `main` evolves. The wiki is reached by replacing `github.com` with `deepwiki.com` in the repo URL.

This proposal opts the repo into that hosted service. It does not stand up a docs site, replace the existing MDX pipeline, or send any code to a third party that doesn't already read it from public GitHub.

## Goals / Non-Goals

**Goals:**
- Give README readers a one-click path to an AI-generated wiki for the repo.
- Keep the wiki current without any maintainer action after merge.
- Keep the existing MDX→MD docs pipeline intact and authoritative for committed markdown.

**Non-Goals:**
- Self-hosting DeepWiki or any OSS variant (deepwiki-open, OpenDeepWiki, RepoWiki). The hosted free tier is sufficient for a public repo of this size.
- Replacing the MDX docs pipeline or migrating to Mintlify/Docusaurus/MkDocs.
- Wiring the DeepWiki MCP server into shared tooling. Individual contributors can register `https://mcp.deepwiki.com/mcp` in their own Claude Code config; that is out of scope for this repo change.
- Authoring a `.devin/wiki.json` outline up front. The default DeepWiki outline is the baseline; a steering file is a follow-up that should be motivated by an observed gap, not by speculation.
- Generating reference docs from Dockerfiles or scripts.

## Decisions

### Use hosted DeepWiki, not a self-hosted alternative

DeepWiki hosted (`deepwiki.com`) is free for public repos, is already operating against this repo's public GitHub URL, and requires zero infra. Self-hosted alternatives (deepwiki-open, OpenDeepWiki, RepoWiki) would require provisioning a server, paying for LLM tokens, and maintaining another service — all to reproduce a free capability. The trade is vendor lock-in to Cognition AI's roadmap, which is acceptable because the integration surface is one badge URL that any replacement could honor or be re-pointed away from.

Source: <https://docs.devin.ai/work-with-devin/deepwiki>, <https://cognition.ai/blog/deepwiki>.

### Source the badge in `docs/src/badges.mdx`, not directly in `readme.md`

`readme.md` is auto-generated and carries the comment `<!--- This markdown file was auto-generated from "readme.mdx" -->`. Editing it directly would be undone by the next compile. The MDX source for the badge row already lives at `docs/src/badges.mdx`. Adding the DeepWiki badge there flows it into the recompiled README and keeps the existing pipeline as the single source of truth.

### Defer `.devin/wiki.json` until a real gap is observed

DeepWiki accepts a `.devin/wiki.json` with `repo_notes` and a `pages` outline that overrides the default page structure. For a repo this small with self-evident structure (clearly named Dockerfiles, scripts, workflows, MDX docs), the default outline is expected to be adequate. Authoring a `pages` list before seeing what DeepWiki produces is speculative, adds a `.devin/` directory contributors must understand, and creates a config that can drift from the codebase. The cheaper path is: ship the badge, observe the generated wiki, then add steering only for the specific gaps that materialize. Adding the file later is a one-PR follow-up with no rework cost.

### Trust badge-presence as the auto-refresh trigger

DeepWiki refreshes wikis automatically for repos that carry a DeepWiki badge in their README. The repo already gets DeepWiki-generated content because it's public; the badge is what unlocks the auto-refresh path. No CI hook, no webhook, no scheduled workflow is needed.

Source: badge generator and behavior described at <https://deepwiki.ryoppippi.com/> and the DeepWiki dev guide.

### Use the standard Shields-style badge

The DeepWiki badge format used widely in the ecosystem is `https://deepwiki.com/badge.svg` linking to `https://deepwiki.com/<owner>/<repo>`. This matches the visual style of the other badges already in the README (OpenSSF Scorecard, channel, Docker version, Docker pulls) and avoids inventing a custom badge.

## Automated Test Strategy

This change has no runtime code path, so the verification surface is small and document-shaped. The critical path is: (1) the badge ends up in the regenerated `readme.md`, (2) the contributing doc gains the new section.

- **Build verification**: run the existing `npm run build` (or `npm run readme` + `npm run contributing`) inside `docs/src/` and confirm both regenerated files reflect the source changes. This is the same pipeline contributors already use; no new infrastructure.
- **Manual smoke check**: open `https://deepwiki.com/gmeligio/flutter-docker-image` after merge and confirm the wiki renders. This is the user-visible outcome and cannot be automated against a third-party service.
- **No new test infrastructure** is introduced.

## Observability

Failures are loud and shallow:
- A broken badge URL would render as a broken-image icon in `readme.md` — visible immediately on GitHub.
- A stale wiki (auto-refresh not firing) would surface to readers as out-of-date page content. Detection: spot-check after notable merges.

There is no silent-failure path that affects image users (the Docker images themselves are untouched). No new logs, metrics, or alerts are warranted.

## Risks / Trade-offs

- **[Vendor dependency on Cognition AI]** → Mitigation: integration surface is one badge URL. If Cognition discontinues the free tier we can remove the badge with no functional regression beyond the wiki page itself, or point the same badge URL at a self-hosted deepwiki-open deployment.
- **[Generated content quality is outside maintainer control]** → Mitigation: the wiki is supplementary to the README, not load-bearing for image users. If the default outline is materially wrong, add `.devin/wiki.json` as a follow-up.
- **[Auto-refresh cadence is undocumented]** → Mitigation: stale-by-a-few-hours is acceptable for a docs surface; no SLA is being promised to readers.

## Migration Plan

Single-PR rollout, no data migration:
1. Add the badge to `docs/src/badges.mdx` and recompile docs.
2. Add the contributing section.
3. Merge.
4. Within DeepWiki's refresh window, the wiki at `deepwiki.com/gmeligio/flutter-docker-image` reflects the latest `main`.

Rollback: revert the PR. The wiki itself remains accessible (DeepWiki indexes public repos regardless), but auto-refresh stops and the badge disappears from the README. No image, CI, or release impact.

## Open Questions

None blocking. The DeepWiki refresh cadence is not publicly documented as a hard SLA, but that is an acceptable unknown for a supplementary docs surface.
