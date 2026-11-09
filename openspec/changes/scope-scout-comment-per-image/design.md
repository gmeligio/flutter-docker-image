# Design

## Context

See proposal.md for motivation. `scan-image` (`.github/workflows/build.yml`) is a matrix over images with `scout: true` in `config/images.json`. It has no checkout step today and already holds `pull-requests: write`. `docker/scout-action` v1.18.2 sets the markdown report as a step output named after the command (`steps.docker-scout.outputs.compare`) per its [README, Output](https://github.com/docker/scout-action#output); the output is not declared in `action.yaml`. Repo convention for github-script logic is a file under `script/` loaded with `require` (`release.yml:104-112`, `script/setEnvironmentVariables.js`).

## Goals / Non-Goals

**Goals:**
- One readable, standalone script that a maintainer can change without touching YAML.
- No new action or package dependency.

**Non-Goals:**
- A single combined comment for all images.
- Type-checking tooling (`tsc`, `package.json`, `tsconfig.json`).
- Cleaning up Scout's old-marker comments on open PRs.
- Changing `release.yml`'s Scout step (push events, no PR comments).

## Decisions

**Upsert per leg, not an aggregator job.** Each leg already holds its own report as a step output; writing from the same leg needs one step. A combined comment would need per-leg artifacts plus a new job, because matrix job outputs collapse to the last leg. Distinct markers mean legs never share state, so parallel writes are safe.

**Marker `<!-- scout-compare:<image> -->` at the start of the body.** Image-scoped, like the artifact name, cache scope and SARIF category discriminators already in the workflows. Matched with `startsWith` and author `github-actions[bot]`, so a user quoting the marker cannot hijack it.

**`actions/github-script` over `gh` CLI.** GitHub-owned, already pinned in this repo (v8.0.0), gives an authenticated Octokit with `paginate`. JS reads more clearly than a `gh api --jq` pipeline.

**TypeScript file run through Node's type stripping.** github-script v8 runs on `node24`; Node 24 strips erasable TypeScript syntax by default ([Node docs](https://nodejs.org/api/typescript.html#type-stripping)). github-script's `require` resolves to Node's own `require` ([README](https://github.com/actions/github-script#run-a-separate-file)), so `require('./script/commentScoutReport.ts')` should load without a build step. Constraints: erasable syntax only (no `enum`, no parameter properties, no `namespace`), CommonJS `module.exports` (no `package.json` → CJS), type-only imports. Types are hand-written for the few fields used, since nothing type-checks in CI.
- Alternative: JS with `// @ts-check` and JSDoc. Kept as fallback if type stripping fails on the runner.

**Inputs via `env`, never `${{ }}` inside the script.** `IMAGE` and `REPORT` reach the script through `process.env`, so report content cannot inject code.

**Sparse checkout of `script/`.** Only the script is needed; keeps the step fast. Same pinned `actions/checkout` SHA as other workflows.

**Truncation.** Body = marker + newline + report. If over 65,536 characters, cut the report and append a line linking `${serverUrl}/${repo}/actions/runs/${runId}`, reserving room for marker and note.

**Gate.** Step `if: github.event_name == 'pull_request' && steps.docker-scout.outputs.compare != ''`. Covers no baseline (Scout skipped), missing output, and `workflow_dispatch`.

## Risks / Trade-offs

- [`outputs.compare` not actually set by v1.18.2] → step is skipped, no comment; the job summary still has the report. Verify on the first PR run; third-party usage of `outputs.cves` / `outputs.recommendations` ([rennf93/parse-docker-scout-output](https://github.com/rennf93/parse-docker-scout-output/blob/main/README.md)) supports it.
- [Runner's Node 24 refuses `.ts` via `require`] → switch the file to `.js` with `@ts-check`; one-line YAML change.
- [Type stripping prints an ExperimentalWarning] → cosmetic log line, no effect.
- [Types are unchecked] → script is ~30 lines; types document intent. Add `tsc` later only if scripts grow.
- [Up to three comments per PR] → accepted; each updates in place.
- [Cancelled run leaves previous comments] → they show last completed results until the next run.

## Migration Plan

Merge; the next PR run creates per-image comments. Old Scout comments on open PRs remain and are never updated. Rollback: revert the commit, restoring Scout's own comment.
