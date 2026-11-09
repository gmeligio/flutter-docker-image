# Design

## Context

See proposal.md and research.md. Spec-only change plus one workflow comment. `build.yml` is the source of truth; specs are rewritten to match it, not the reverse.

## Goals / Non-Goals

**Goals:**
- Each PR-pipeline rule lives in exactly one spec.
- Specs name checks by display name (`Test image (<name>)`) and images generically (`<image>`).

**Non-Goals:**
- Workflow behavior changes.
- Other specs missing `## Purpose` (#561), CI spec validation (#598), `config.yaml` audience (#599).
- `ci-workflow-readability:39`: names `build_image` on purpose (rename example).
- Splitting existing >500-char requirements to satisfy `--strict`.

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

## Risks / Trade-offs

- [Archive history shows no REMOVED delta for the deleted spec] → D1 table records it; PR description links #597.
- [MODIFIED blocks replace whole requirements] → scenario names kept so archive does not reject dropped scenarios (verified with `openspec validate --strict`).
