# Design

## Context

See proposal.md for motivation. `scan-image` (`.github/workflows/build.yml`) is a matrix over images with `scout: true` in `config/images.json`. It has no checkout step today and already holds `pull-requests: write`. `docker/scout-action` v1.18.2 (the pinned version; all claims here are about it) exposes the markdown report two ways: an undeclared step output named after the command ([README, Output](https://github.com/docker/scout-action#output)), and the `format`/`output` inputs, which map to `docker scout compare --format markdown --output <file>` ([CLI docs](https://docs.docker.com/reference/cli/docker/scout/compare/)). The job's `permissions:` block lists no `contents`, so a checkout needs `contents: read` added. Repo convention for github-script logic is a file under `script/` loaded with `require` (`release.yml:104-112`, `script/setEnvironmentVariables.js`).

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

**Upsert per leg, not an aggregator job.** Each leg already holds its own report as a step output; writing from the same leg needs one step. A combined comment would need per-leg artifacts plus a new job, because matrix job outputs collapse to the last leg. Distinct markers mean legs never share state, so parallel writes are safe. Across runs, `build.yml`'s `concurrency` group (`${{ github.workflow }}-${{ github.head_ref || github.ref_name }}`, `cancel-in-progress: true`) keeps one run per PR, so two runs do not race to create the same image's comment. If duplicates exist anyway, the script updates the oldest (first in the ascending list) and deletes the rest, so the PR returns to one comment per image.

**Marker `<!-- scout-compare:<image> -->` at the start of the body.** Image-scoped, like the artifact name, cache scope and SARIF category discriminators already in the workflows. Matched with `startsWith` and author `github-actions[bot]`, so a user quoting the marker cannot hijack it.

**`actions/github-script` over `gh` CLI.** GitHub-owned, already pinned in this repo (v8.0.0), gives an authenticated Octokit with `paginate`. JS reads more clearly than a `gh api --jq` pipeline.

**TypeScript file run through Node's type stripping.** github-script v8 runs on `node24`; Node 24 strips erasable TypeScript syntax by default ([Node docs](https://nodejs.org/api/typescript.html#type-stripping)). github-script's `require` resolves to Node's own `require` ([README](https://github.com/actions/github-script#run-a-separate-file)), so `require('./script/commentScoutReport.ts')` loads without a build step. Verified: github-script v8.0.0's own `dist/index.js` (SHA `ed59741`) on Node 24.22.2, the runner's bundled `NODE24_VERSION` ([actions/runner externals.sh](https://github.com/actions/runner/blob/main/src/Misc/externals.sh)), loaded a `.ts` file using `import type`, `interface`, `type` and `satisfies`, exit 0, no warning. Constraints: erasable syntax only (no `enum`, no parameter properties, no `namespace`), CommonJS `module.exports` (no `package.json` → CJS), type-only imports. Types are hand-written for the few fields used, since nothing type-checks in CI.
- Alternative: JS with `// @ts-check` and JSDoc. Rejected: the maintainer asked for TypeScript; inline type syntax is shorter and easier to read than JSDoc comments, and editors' TypeScript language service still checks it locally without a `tsconfig`. CI checks neither form, so JSDoc would buy nothing extra.

**Report travels as a file, not a string.** Scout writes `${{ runner.temp }}/scout-compare.md` (`format: markdown`, `output:`); the script reads it with `fs`. Each leg runs on its own runner, so the path needs no image suffix.
- Alternative: step output passed via `env`. Rejected: Linux caps one env string at 128 KiB (`MAX_ARG_STRLEN`), so a large report fails process spawn before truncation runs; it also depends on an output the action does not declare.

**Inputs via `env`, never `${{ }}` inside the script.** `IMAGE` and `REPORT_FILE` reach the script through `process.env`, so nothing from the report or matrix is evaluated as code.

**Visible heading.** Body = marker, then `### Docker Scout compare: <image>`, then the report. The marker is invisible; the heading tells the reader which image the comment covers without relying on Scout's report text.

**Sparse checkout of `script/`.** Placed before the logins and Scout, so a Scout failure cannot skip it. Only the script is needed; keeps the step fast. Same pinned `actions/checkout` SHA as other workflows. Running PR-branch code with `pull-requests: write` is safe because the job-level fork gate (`ci-parallel-image-validation`, "Scan job preserves the existing fork-PR gate") limits `scan-image` to same-repo PRs, whose authors already have write access.

**Truncation.** If the body's JS `length` exceeds 65,536, cut the report and append a line linking `${serverUrl}/${repo}/actions/runs/${runId}`, reserving room for marker, heading and note. JS `length` counts UTF-16 code units, which is never less than the code-point count GitHub limits, so the cut is conservative.

**Gate.** Step `if: ${{ !cancelled() && github.event_name == 'pull_request' && steps.docker-scout.outcome != 'skipped' }}`. Covers no baseline (Scout skipped) and `workflow_dispatch`, and still runs when Scout failed. A missing or empty report file means Scout failed or ran without a report: the script emits `core.warning` and returns, so the gap is visible on the run.

**Comment errors are warnings.** The inline `script:` wraps the whole call, `require` included, in one `try/catch` that turns any error (load, file read, API) into `core.warning` naming the image. Keeps the scan advisory (`Scan output remains advisory, not gating`). Alternative: `continue-on-error: true` on the step. Rejected: it shows a failed step with an error annotation, not a warning.

## Risks / Trade-offs

- [Action ignores `format`/`output` for `compare`] → script warns "no report" on every leg, scan stays green, job summary still has the report. Public workflows pass these inputs with `cves`/`sbom` ([nedix/actions](https://github.com/nedix/actions), [thebackendofluck/book](https://github.com/thebackendofluck/book)); task 3.1 confirms for `compare`. If it does not, implementation stops and this design is revised; there is no fallback.
- [`--output` moves the report out of the step log] → the job summary and the PR comment still carry it.
- [An image is switched to `scout: false` after it was commented] → its comment stays on open PRs. Accepted: rare, and the comment still describes the last scan.
- [A later Scout run fails] → the previous comment stays unchanged while the run shows a warning. Accepted: the warning plus the red leg tell the reader the comment is not current.
- [A step before Scout fails (login, digest)] → Scout is skipped, so no comment and no warning; the failed earlier step already explains the red leg.
- [A baseline disappears after an image was commented] → the old comment stays unchanged. Accepted: published release tags are never deleted, so this does not happen in practice.
- [A runner Node bump changes type-stripping behavior] → Node 24 type stripping is stable; non-erasable syntax is the only way to break it, and the constraint is documented above.
- [Types are unchecked] → script is ~30 lines; types document intent. Add `tsc` later only if scripts grow.
- [One comment per scanned image] → accepted; each updates in place.
- [Cancelled run leaves previous comments] → they show last completed results until the next run.

## Migration Plan

Merge; the next PR run creates per-image comments. Old Scout comments on open PRs remain and are never updated. Rollback: revert the commit, restoring Scout's own comment.
