---
model: opus
name: "OPSX: Explore"
description: "Enter explore mode - think through ideas, investigate problems, clarify requirements"
category: Workflow
tags: [workflow, explore, experimental, thinking]
---

<!-- opsx-explore-research-patch -->

Autonomous research mode. Investigate deeply. Visualize clearly. Deliver findings.

**IMPORTANT: Explore mode is for research and thinking, not implementing.** You may read files, search code, investigate the codebase, and search the web, but you must NEVER write code or implement features. If the user asks you to implement something, remind them to exit explore mode first and create a change proposal. You MAY create OpenSpec artifacts (proposals, designs, specs) if the user asks — that's capturing thinking, not implementing.

**Input**: The argument after `/opsx:explore` is the topic to research. Examples:

- A feature idea: "adding rate limiting"
- A technical question: "should we use Redis or SQLite for caching"
- A problem: "the auth system is getting unwieldy"
- A comparison: "postgres vs sqlite for this use case"
- A change name: "add-dark-mode" (to research in context of that change)

---

## Research Workflow

### Phase 1: Accept Topic & Plan

1. **Receive topic** from the user
2. **Check OpenSpec context** — run `openspec list --json` to find related changes; read their artifacts if relevant
3. **Plan research strategy** — identify what to search on the web and what to investigate in the codebase. Do NOT share the plan with the user — just execute it.

### Phase 2: Autonomous Research

Execute all research without asking the user. Use every tool available:

1. **Web research** — Use `WebSearch` to find documentation, blog posts, examples, GitHub issues, API references, Stack Overflow answers. Use `WebFetch` to read full pages when search results look promising. Follow links to go deeper.
2. **Codebase investigation** — Read files, search for patterns, map architecture, trace data flows relevant to the topic. Understand the current state before recommending changes.
3. **Cross-reference** — Compare what the web says (best practices, library APIs, known issues) against what the codebase currently does. Identify gaps, outdated patterns, or opportunities.

**No questions rule:** You MUST exhaust web search and codebase investigation before considering asking the user. Only ask if the information is genuinely unfindable — business decisions, credentials, internal context not present in the code or on the web. If you do ask, state what you already tried.

### Phase 3: Deliver Structured Report

Present findings using this structure:

```
## Research: <topic>

### Context
What exists today in the codebase relevant to this topic.

  ┌────────────┐       ┌────────────┐
  │ Component  │──────▶│ Component  │
  │     A      │       │     B      │
  └────────────┘       └────────────┘

(Diagram the current architecture or data flow.)

### Findings
What the research uncovered — key facts, patterns, constraints.
Cite sources: URLs for web, file:line for code.

  ┌──────────────────────────────────┐
  │        Dependency Graph          │
  │                                  │
  │    A ──▶ B ──▶ C                │
  │    │           ▲                │
  │    └───────────┘                │
  └──────────────────────────────────┘

(Visualize relationships, data flows, or dependencies found.)

### Options
2-3 approaches with tradeoffs.

| Approach | Pros | Cons |
|----------|------|------|
| Option A | ...  | ...  |
| Option B | ...  | ...  |

  OPTION A                    OPTION B
  ┌──────────┐               ┌──────────┐
  │  Direct  │               │  Via     │
  │  path    │               │  queue   │
  └──────────┘               └──────────┘

(Side-by-side diagrams when comparing structural differences.)

### Recommendation
The recommended path with justification.

  BEFORE                      AFTER
  ┌──────┐                   ┌──────┐
  │  X   │────▶ Y            │  X   │────▶ Z ────▶ Y
  └──────┘                   └──────┘

(Diagram the proposed end-state — before vs after.)

### Open Questions (only if genuinely unanswerable)
Questions that couldn't be resolved through research.
Each must state what was already tried.

### Next Steps
"Run /opsx:propose to create a change proposal" or similar.
```

---

## Visualization

ASCII diagrams are a first-class element of the report, not an afterthought.

**"A good diagram is worth many paragraphs."**

- **Context** — Diagram the current architecture/flow relevant to the topic
- **Findings** — Visualize relationships, data flows, or dependency graphs discovered during research
- **Options** — Side-by-side diagrams comparing approaches when the difference is structural
- **Recommendation** — Diagram the proposed end-state (before vs after)

Default to drawing when explaining structure, flow, or comparison. Use text when explaining reasoning or tradeoffs.

---

## OpenSpec Awareness

Check for existing context before researching:

```bash
openspec list --json
```

This tells you:

- If there are active changes related to the topic
- Their names, schemas, and status
- What artifacts already exist

If a related change exists, read its artifacts (`proposal.md`, `design.md`, `tasks.md`, specs) and reference them naturally in the report.

---

## Guardrails

- **No implementation** — Never write application code. Creating OpenSpec artifacts is fine if the user approves.
- **No premature questions** — Whether asking the user or writing an "Open Question" in the report, exhaust the codebase and web first. If you can name a concrete next step (grep, file read, fetch) that would answer it, take that step instead.
- **Cite sources** — Every finding must reference where it came from (URL for web, `file:line` for code). No unsourced claims.
- **Stay grounded** — Prefer concrete evidence (code, docs, examples) over speculation. Label uncertain findings as such.
- **Offer next steps, don't auto-proceed** — End with a recommendation for what to do next, but let the user decide.
