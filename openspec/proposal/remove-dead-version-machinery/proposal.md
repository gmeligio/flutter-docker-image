# Remove dead version machinery — issue #534

## Findings that change the scope

- **Seven scripts are currently unreferenced, not nine.** The other 12 have live consumers; use the audited list rather than the historical count ([F2](findings.md#f2--refuted-nine-current-scripts-have-no-repository-consumers)).
- **The cmdlineTools mirror is unused by the build, but used by test generation.** Removing it alone breaks the generator and schema validation ([F3](findings.md#f3--refuted-the-cmdlinetools-field-has-no-live-consumers)).
- **The two workflow defaults are redundant.** The manifest exporter replaces them before building; removing them produces identical exports ([F5](findings.md#f5--confirmed-the-two-stale-job-defaults-do-not-change-exported-build-arguments)).

## Impact

| Change | Measurable scope | Behavior |
|---|---|---|
| Remove unused helpers | Seven deletions; tracked scripts fall from 19 to 12 ([F2](findings.md#f2--refuted-nine-current-scripts-have-no-repository-consumers)) | No known repository entry point changes |
| Remove job defaults | Two workflows ([F5](findings.md#f5--confirmed-the-two-stale-job-defaults-do-not-change-exported-build-arguments)) | Build arguments unchanged |
| Remove the mirror coherently | One manifest field and its consumers across four files ([F3](findings.md#f3--refuted-the-cmdlinetools-field-has-no-live-consumers)) | Existing exact-revision test is preserved unchanged |

Total implementation scope: **13 existing files** — seven deleted, six modified, as enumerated below.
No new dependencies, updater, or permanent CI check is needed.
All eight command tests and both file-content tests must remain unchanged.

## Goal

Remove unused machinery while preserving all live build/update entry points and useful image coverage.

## Problem

Small obsolete wrappers read as supported infrastructure, while redundant workflow values obscure the actual manifest source of truth ([F2](findings.md#f2--refuted-nine-current-scripts-have-no-repository-consumers), [F5](findings.md#f5--confirmed-the-two-stale-job-defaults-do-not-change-exported-build-arguments)).
The command-line-tools revision is maintained as an expected test value even though installation dynamically selects an upstream archive ([F3](findings.md#f3--refuted-the-cmdlinetools-field-has-no-live-consumers), [F4](findings.md#f4--confirmed-the-installed-command-line-tools-revision-is-not-selected-by-the-manifest)).

**Agreed policy:** retain the existing dynamic installer and the exact `22.0` assertion in the test fixture.
The maintainer requires this reviewed-revision drift gate: a changed upstream revision must still fail the test.
Remove the duplicate manifest value and generation plumbing, not the test guarantee.
Real archive pinning is a separate change, not a prerequisite for removing the mirror ([option disposition](hypothesis.md#option-disposition)).

## Plan

Ship one PR with three independently reviewable commits.

### 1. Delete unused scripts

Delete exactly the seven files listed in [F2](findings.md#f2--refuted-nine-current-scripts-have-no-repository-consumers).
Keep the live test generator, Renovate validator, image verification script, and every other script with a current consumer.
Recheck basename and dynamic call sites against the implementation checkout, excluding historical archives and these research documents.

**Decision gate:** ship if the recheck remains empty and the maintainer has no external dependency on the helpers.
Abandon any individual deletion if a current or external consumer is identified; do not recreate a wrapper just to preserve the historical count.

### 2. Delete overwritten workflow defaults

Remove `ANDROID_BUILD_TOOLS_VERSION: 30.0.3` from [CI](../../../.github/workflows/ci.yml#L25-L28) and [Linux release](../../../.github/workflows/release.yml#L88-L90).
Remove CI's resulting empty job `env` mapping; keep the other release environment entries.
Leave the manifest exporter and shared build arguments unchanged.

**Decision gate:** ship if workflow validation passes and a before/after exporter check produces identical values.
Abandon the deletion if a new pre-export consumer is found.

### 3. Remove the cmdlineTools mirror as one coordinated change

| File | Change |
|---|---|
| [config/version.json](../../../config/version.json#L19-L25) | Remove `android.cmdlineTools` |
| [config/schema.cue](../../../config/schema.cue#L69-L76) | Remove its required-field declaration; retain the semver definitions used elsewhere |
| [script/update_test.sh](../../../script/update_test.sh#L9-L19) | Remove cmdline-tools extraction, expected-content construction, obsolete guard, both CUE tags, and progress-message reference |
| [config/android.cue](../../../config/android.cue#L65-L67) | Remove both cmdline-tools tags; pass through file-content tests instead of rewriting the first one |

Leave [test/android.yml](../../../test/android.yml#L93-L104) byte-for-byte unchanged, including its exact `22.0` expectation and analytics coverage.
The generator must preserve that fixture rather than deriving the command-line-tools revision from the manifest.
Do not change the ordering or assertions of command tests; the generator currently uses positional indexing ([F9](findings.md#f9--confirmed-pass-through-metadata-coverage-needs-no-cmdline-tools-tags)).

**Decision gate:** ship if schema validation, regeneration, docs generation, and the existing Android image tests pass.
Abandon this phase if regeneration changes the reviewed revision or any other existing assertion.

## Acceptance evidence

- Re-audit remaining scripts for direct and dynamic references.
- Run the existing CUE validation for version and image manifests.
- Run `script/update_test.sh` twice: both runs must reproduce the original test fixture byte-for-byte.
- Compare the entire test fixture with the baseline, including all command and file-content tests.
- Run `mise run docs`; removal of the test-only field should not alter generated docs.
- Exercise the original exact-revision check with Container Structure Test; confirm the installed revision passes and a different revision fails.
- Let normal PR workflow checks exercise the retained entry points.

The analysis already checked baseline schemas, baseline test regeneration, equivalent environment exports, and scratch CUE pass-through feasibility ([F5](findings.md#f5--confirmed-the-two-stale-job-defaults-do-not-change-exported-build-arguments), [F6](findings.md#f6--confirmed-existing-schema-validation-and-test-regeneration-pass-at-the-research-baseline), [F9](findings.md#f9--confirmed-pass-through-metadata-coverage-needs-no-cmdline-tools-tags)).
Subsequent verification completed the full Android suite against published image `3.47.2`: all ten tests passed. The original static assertion also rejected revision `23.0`.
See [validation results](validation.md) for the commands, evidence, and remaining scope boundary. No fresh image build was run.

## Scope boundary

Do not edit historical OpenSpec archives, expand the cleanup to other manifest fields, alter Dockerfile installation policy, or change Renovate.
The `.env.example` value is still a live Compose input and belongs to separate local-configuration work ([F8](findings.md#f8--confirmed-the-local-environment-example-still-has-a-live-3003-value)).
