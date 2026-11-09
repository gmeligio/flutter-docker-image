# Design

## Context

See proposal.md and research.md. `build.yml` is the source of truth for the image pipeline; specs are rewritten to match it, not the reverse. The only new CI is the spec validation check (D6).

## Goals / Non-Goals

**Goals:**
- Each PR-pipeline rule lives in exactly one spec.
- Specs name checks by display name (`Test image (<name>)`) and images generically (`<image>`).
- `openspec validate --all` is green and stays green via CI.

**Non-Goals:**
- Image-pipeline behavior changes.
- `ci-workflow-readability:39`: names `build_image` on purpose (rename example).
- Splitting existing >500-char requirements to satisfy `--strict`.
- Making `Validate specs` a required check (D6).

## Decisions

**D1. Delete `ci-parallel-image-validation` directly, without a REMOVED delta.**
A delta removing all four requirements makes `openspec archive` rebuild an empty, Purpose-less spec, fail validation, and abort (tested on a scratch copy, openspec 1.16.1). Deleting `openspec/specs/ci-parallel-image-validation/` during apply, with no delta for it, archives cleanly (also tested). Removal rationale per requirement:

| Old requirement | Destination |
|---|---|
| Test and scan run as sibling jobs | `ci-image-handoff`: Test and scan validate each image in parallel after build |
| Consumer jobs do not rebuild the image | `ci-image-handoff`: Consumer jobs never rebuild the image |
| Scan job preserves the existing fork-PR gate | `ci-image-vulnerability-scan`: Scan is skipped for fork PRs at the job level |
| Renamed consumer preserves the existing required-check name | Dropped: one-time migration done in #477 |

Alternative: keep the spec with only the parallel requirement. Rejected — it would still split the build→consume chain across two specs.

**D2. Fold into `ci-image-handoff`, not a new `pr-image-pipeline` spec.** Same benefit, smaller diff, no rename of a spec other docs cite.

**D3. Drop timing thresholds** ("within 30 seconds", `max(...)` wall-clock) from the parallel requirement. They depend on runner queueing, not on this repo; the testable rule is "no `needs` edge between test and scan".

**D4. `ci-image-handoff` Purpose is edited in the main spec directly**, since deltas ignore `## Purpose` for existing capabilities.

**D5. #561 Purposes are edited in the main specs directly** (same reason as D4). `ci-image-anonymous-availability` and `generated-docs-and-examples` also get the `# <name> Specification` title and `## Requirements` header they lack. Texts:

| Spec | Purpose |
|---|---|
| `ci-image-handoff` | Hand each image built by `build-image` to the `test-image` and `scan-image` legs of the same run without rebuilding it: a GHCR handoff tag for same-repo events, a per-image artifact for fork PRs. |
| `ci-image-anonymous-availability` | Guarantee every image a release publishes is pullable without registry credentials, verified by the release run against exactly the set it published, so a CI engineer's copied pull command works on any runner. |
| `generated-docs-and-examples` | Generate `readme.md` and the four CI examples from `config/version.json` and `config/images.json`, so the README and examples always show the versions and images actually published. |
| `repository-wiki` | Give CI engineers a one-click, automatically refreshed DeepWiki for this repository, linked from the README, and tell contributors how it works. |
| `windows-version-tracking` | Track the Windows image toolchain versions in `config/version.json`, so the Dockerfile, Pester tests, and scheduled upgrade PR all read one source. |

**D6. Spec validation: `mise run specs` → `openspec validate --all`, in a new `openspec.yml` workflow.**
- `--all` covers specs and active changes; non-strict because `--strict` fails nearly every spec on >500-char warnings (Non-Goal).
- New workflow, not a `gx.yml` job: `gx.yml` triggers on workflow paths only and its name says what it lints. Workflow `OpenSpec`, job `validate`, `name: Validate specs`, on `pull_request` paths `openspec/**`, `mise.toml`, `.github/workflows/openspec.yml`, plus `workflow_dispatch`. Follows `ci-workflow-hardening` (harden-runner, `permissions: contents: read`, SHA pins via `gx`) and `ci-runtime-tool-versioning` (`jdx/mise-action`).
- Not a required check: a path-filtered workflow never reports on unrelated PRs, so requiring it would block them.
- Alternative: a `pre-commit`-style local hook only. Rejected — solo maintainer, CI is the only reliable gate.

**D7. `openspec/config.yaml` audience is "the CI engineer or maintainer".** `rules.specs` replaces every "desktop user" with it. `context:` today limits specs to what "a CI engineer or developer would notice when pulling, running, or building with these images", which excludes maintainer-facing CI specs that already exist (`ci-repo-governance`, `ci-workflow-hardening`); it is widened to also cover what the maintainer notices when building, releasing, or reviewing changes to the images. Add `CRITICAL: Reject requirements that describe a one-time migration or rollout step; put those in design.md or tasks.md`. `rules.proposal` unchanged. Existing specs that say "desktop user" (e.g. `ci-runtime-tool-versioning` Purpose) are left alone.

## Risks / Trade-offs

- [Archive history shows no REMOVED delta for the deleted spec] → D1 table records it; PR description links #597.
- [MODIFIED blocks replace whole requirements] → scenario names kept so archive does not reject dropped scenarios (verified with `openspec validate --strict`).
- [`Validate specs` is advisory, so a red check can still be merged] → solo maintainer merges by hand; acceptable. Revisit if the check is ever moved to an always-run workflow.
- [`openspec validate --all` fails on any other in-flight change, e.g. `ubuntu-26-runners`] → intended; it passes today.
