---
model: opus
name: openspec-init
description: Generate or refresh openspec/config.yaml for a project. Use when bootstrapping openspec in a new project or when updating a drifted config.
license: MIT
compatibility: Requires openspec CLI.
metadata:
  author: agent-skills
  version: "1.1"
---

Generate, refresh, or review `openspec/config.yaml` for the current project.

### Mode selection (run before Step 1)

If `openspec/config.yaml` already exists, decide intent from the invocation argument:

- Argument contains `review` (or no argument and the file exists) → **review mode**: read the file, judge whether it is well-tailored to the project, report strengths/observations, and stop. Do not propose a regeneration; do not flatten a project-tailored config back to generic template wording. Skip Steps 1–3 and Step 5.
- Argument contains `refresh`, `regenerate`, `rewrite`, or the file is missing → **generate mode**: continue with Step 1.

---

## Step 1 — Detect project name and description

Check the following sources in order, stopping at the first hit:

1. `package.json` — `name` + `description`
2. `pubspec.yaml` — `name` + `description`
3. `Cargo.toml` — `[package].name` + `description`
4. `pyproject.toml` — `[project].name` + `description`
5. `README.md` — H1 title + first non-empty paragraph after it
6. `AGENTS.md` or `CLAUDE.md` — first paragraph

Tell the developer which source you used. If no source yields a description, ask the developer (warning, not hard failure). Do not write a placeholder.

---

## Step 2 — Identify persona and scope

Ask two questions (developer can override either suggestion):

1. **"Who notices changes to this project?"** → `<persona>`
2. **"What's the unit of scope a spec describes?"** → `<scope-noun>`

Suggest a framing as a starting point:

| Framing | When to suggest | Default persona | Default scope-noun |
|---|---|---|---|
| `product` | CLI tools, libraries, mobile/web apps with end-users | `user` (or named role like `shopper`, `reader`) | `user capabilities` or `<role> workflows` |
| `environment` | Dotfiles, system setup, agent skills, developer tooling | `desktop user` or `developer or their agent` | `experience contexts` |

For `product` with a named role, also ask: **"What is the role name?"** That name replaces `user` throughout the config.

---

## Step 3 — Compose the config

Build the candidate `openspec/config.yaml`. **The `context:` field must be at most two sentences**: one that identifies the project, one that names the scope of what specs cover. No gate items, no bullet lists, no rationale — those belong under `rules.proposal`.

```yaml
schema: spec-driven

context: |
  <project-name> is <one-paragraph description from Step 1>. Specs cover changes that affect <scope-noun>.

rules:
  proposal:
    <gate items — see template below>
    <skip items — see baseline below>
    - Justify why this change requires a spec (reference the gate items above)
  specs:
    <canonical specs block, with <persona> and <scope-noun> substituted>
```

### Gate template (used by both framings)

Always include these two:

```yaml
    - "Spec required: adds, removes, or changes <persona>-visible behavior"
    - "Spec required: introduces a domain concept that changes <scope-noun>"
```

`environment` adds one more, phrased to match the project (packages/services for system setups, skills/workflows for agent tooling):

```yaml
    - "Spec required: adds or removes <packages, services, skills> that alter the available experience"
```

### Skip baseline (single source of truth)

```yaml
    - "Skip spec: internal refactoring with no <persona>-visible change"
    - "Skip spec: tooling, packaging, dependency, or documentation-only changes"
    - "Skip spec: bug fix with obvious solution"
    - "Skip spec: would duplicate an existing spec"
```

`environment` adds one more (only when relevant — system-style projects):

```yaml
    - "Skip spec: single package add/remove or preference tweak (keybinding, alias, color)"
```

### Canonical specs block (substitute `<persona>` and `<scope-noun>`)

```yaml
    - Every spec must trace to something the <persona> would notice or care about
    - Name the experience context where the change is noticed
    - Use GIVEN/WHEN/THEN format for behavioral scenarios
    - Architectural guardrails are constraints on how value is delivered to the <persona> — they must be load-bearing (violating one would degrade the <persona>'s experience)
    - Error classification determines whether the <persona> sees a warning or hard failure
    - On archive, sync the spec to reflect the shipped behavior
    - "CRITICAL: Reject if spec has no traceable impact on the <persona>'s experience"
    - "CRITICAL: Reject if spec describes implementation without connection to what the <persona> would notice"
    - "CRITICAL: Reject if change contradicts or duplicates an existing spec's experience impact"
    - "WARNING: Guardrail not justified as load-bearing"
    - "WARNING: Missing GIVEN/WHEN/THEN for claimed behaviors"
    - "WARNING: Scope too broad — multiple unrelated <scope-noun>"
```

---

## Step 4 — Preview and confirm

Check that the existing file (if any) is valid YAML — if parsing fails, print the error and exit without modifying any file (hard failure). Then show a unified diff for update mode, or the full candidate for create mode.

Ask: "Ready to write `openspec/config.yaml`. Confirm? (y/n)". If declined, exit and print the candidate for copy-paste.

---

## Step 5 — Write the file

Create `openspec/` if needed (`mkdir -p openspec`) and write the confirmed candidate to `openspec/config.yaml`. Do not run any `openspec` CLI commands — those are the developer's next steps. Print: `"Written: openspec/config.yaml"`
