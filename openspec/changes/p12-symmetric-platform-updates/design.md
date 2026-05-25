## Context

`update_version.yml`'s monthly upgrade flow grew incrementally: Flutter first, then Android, then Windows (via `p3-windows-version-schema`), then resilience hardening for Windows (`p11-resilient-windows-update`). Each platform was bolted on without revisiting the composition model, leaving three structural asymmetries:

1. **Artifact shape**: Android emits the full `config/version.json` (with `flutter` and `android` blocks merged via `script/copyFlutterVersion.js`); Windows emits only a fragment containing the `windows` block.
2. **Failure propagation**: After `p11`, Windows-job failure is soft (PR opens with carried-forward `windows` block). Android-job failure is hard (PR is blocked).
3. **Composition order vs validation**: `validate_config_version` runs against Android's *partial* output (no new `windows` block yet); the PR job then performs a second composition (overlaying Windows) and re-validates. Composition happens on both sides of the validation gate.

None of these asymmetries is load-bearing. The artifact-shape difference is historical. The failure-propagation difference reflects what was easy to fix in p11, not a documented requirement. The composition-vs-validation ordering is a bug — a malformed Windows fragment is only caught by the PR job's CUE re-validation, not by the dedicated validation job. The single-gate property the workflow visually presents is illusory.

The base-branch checkout's `config/version.json` is always schema-valid (enforced by `build.yml`'s `validate_version_files` job on every PR). That makes it a safe composition canvas: each platform block on it has been validated at least once, and carrying a block forward unchanged is by definition a no-op against schema. The current design ignores this; the symmetric model leans on it.

## Goals / Non-Goals

**Goals:**

- One composition step, one validation gate. The composed `config/version.json` is built in exactly one place, validated in exactly one place, and consumed read-only by everything after.
- Symmetric platform-update model. Android and Windows behave identically from the workflow graph's perspective: each is a fragment producer; either can skip; the compose step tolerates either being absent.
- The PR-creation job has no business logic over `config/version.json` — it downloads, it reads env vars, it opens the PR. No `jq`, no overlay, no re-validation.
- Preserve existing data contracts. The committed `config/version.json` schema is unchanged. The PR's resulting `config/version.json` is byte-equivalent to today's output on the happy path.

**Non-Goals:**

- Changing the schema or any per-platform extractor logic. Android's Gradle workflow, Flutter's packages.txt parsing, and Windows's vsman parsing are all unchanged.
- Eliminating `validate_config_version`. This change moves *what* it validates, not whether the gate exists. The dedicated gate is preserved.
- Touching image-build workflows (`windows.yml`, `release.yml`) or the test suites. The version manifest's consumers downstream of `update_version.yml` are unaffected.
- Introducing parallelism between Android and Windows beyond what already exists. Both already run in parallel after Flutter; that stays.

## Decisions

### Decision: Each platform updater emits only its block as a fragment

`update_android_version` emits an artifact containing only the `android` block (and the `flutter` block — see below for why); `update_windows_version` continues to emit a fragment containing only the `windows` block (already the case after `p11`).

The fragment is a complete `version.json`-shaped document with all other blocks zeroed out or omitted, depending on what `jq` overlay semantics need. The compose step uses `jq`'s `*` (recursive merge) or `+` (object merge) operators against the base manifest, so the fragment's only meaningful content is its own block.

Alternatives considered:

- **Full version.json from both producers.** Rejected: forces a 3-way merge in the compose step (each producer sees the OLD other-platform block at the time of writing) and obscures which block is authoritative for which producer.
- **Inline blocks in producer job outputs (not artifacts).** Rejected: GitHub Actions outputs are size-limited and not designed for structured data; artifacts are the right delivery mechanism for files.

### Decision: Flutter overlay moves to the compose job

`script/copyFlutterVersion.js` currently runs inside `update_android_version` and is responsible for two things: (1) merging the Flutter block into `config/version.json`, and (2) exporting `FLUTTER_VERSION`/`FLUTTER_CHANNEL` to `$GITHUB_ENV`. These are conflated.

In the new model:

- The *merge* moves into `compose_version_manifest`. The compose job calls the same script (or an equivalent `jq` pipeline) to overlay the Flutter block onto the base manifest. This makes Flutter symmetric with Android and Windows — also a fragment, also overlaid in compose.
- The *env-var export* moves to `update_docs_and_create_pr`, where those vars are actually consumed (for the commit message, branch name, etc.). The script is called against the validated composed manifest at that point.

This means `copyFlutterVersion.js` gets factored into two responsibilities or kept as one script called from two places. Decision: keep it as one script. It's a tiny module; the duplication-of-call-site is cleaner than a split that splits a 50-line file across two utilities.

Alternatives considered:

- **Inline the overlay directly in `compose_version_manifest` and delete `copyFlutterVersion.js`.** Rejected: the script also handles env-var export, which is still needed by `update_docs_and_create_pr`. Keeping the script lets us call it from both jobs with the same behavior.
- **Have Flutter overlay happen in `update_flutter_version` itself (so it emits a partial composed manifest).** Rejected: that re-introduces the asymmetry — Flutter would be a "composer" and the others "fragment producers", and the compose step would have a different starting state depending on whether Flutter ran. Cleaner to treat all three platforms identically.

### Decision: `compose_version_manifest` is a new job between platform updaters and validation

The compose step is large enough to merit its own job (separate workspace, separate log surface, dedicated `needs:` line). It does:

1. Check out the base branch (to obtain the schema-valid `config/version.json` and `test/android.yml`).
2. Download Flutter's artifact (always present — pipeline is gated on Flutter changing).
3. Conditionally download Android's fragment (when `needs.update_android_version.outputs.version_artifact_id != ''`).
4. Conditionally download Windows's fragment (when `needs.update_windows_version.outputs.version_artifact_id != ''`).
5. Conditionally download Android's `test/android.yml` artifact (same condition as 3).
6. Overlay Flutter block onto base. Overlay Android block if downloaded; otherwise carry forward base. Overlay Windows block if downloaded; otherwise carry forward base.
7. Upload composed `config/version.json` and `test/android.yml` (either fresh or carried-forward) as a single `composed-manifest` artifact.

The job runs with `if: !cancelled() && needs.update_flutter_version.result == 'success'` so it executes whenever Flutter has produced a fragment, regardless of whether the platform jobs succeeded.

Alternatives considered:

- **Compose inline at the start of `validate_config_version`.** Rejected: conflates two responsibilities. A failing validation should fail loudly, and entangling that with composition makes "did composition fail or did validation fail?" harder to read in the logs.
- **Compose inline at the start of `update_docs_and_create_pr`.** Rejected: violates the "PR job is read-only" goal. Also: validation would run BEFORE composition in the workflow graph (since `validate_config_version` is a separate job), which is what we're fixing.

### Decision: `validate_config_version` consumes the composed artifact

After this change, `validate_config_version`'s `needs:` is `compose_version_manifest` (instead of `update_android_version`), and it downloads the composed `config/version.json` artifact. Its CUE check now sees the *only* version of the manifest that will become the PR's content. If composition introduced a malformed block, this gate catches it before any PR work happens.

### Decision: `update_docs_and_create_pr` is downstream-only

The PR job's `needs:` becomes `[compose_version_manifest, validate_config_version]` (the platform-updater jobs are no longer direct dependencies). Its steps:

1. Checkout base.
2. Download `composed-manifest` artifact (overwrites `config/version.json` and `test/android.yml`).
3. Run `script/setEnvironmentVariables.js` against the composed manifest (unchanged behavior).
4. Run `script/copyFlutterVersion.js` to export `FLUTTER_VERSION`/`FLUTTER_CHANNEL` env vars (no file mutation — the script's overlay is idempotent against an already-overlaid manifest).
5. Build docs (`pnpm install`/`build`) — unchanged.
6. Compose the PR body (with annotations for any skipped platforms).
7. Create the PR.

No `jq` calls against `config/version.json`. No validation step. No artifact overlay logic.

### Decision: Symmetric `<platform>_skipped` outputs and uniform PR body annotation

Both `update_android_version` and `update_windows_version` expose a `<platform>_skipped` job output (`'true'` when no fragment was produced, `'false'` otherwise). The PR job composes the PR body with per-platform annotation lines, linking each skipped platform to its job log.

For Android, the "skipped" condition is simply "the job did not produce an artifact" — there's no equivalent of Windows's release-identity check today. The output is set in a final step that runs `if: always()` and inspects `steps.upload-version.outcome`. If the job fails partway through (e.g., packages.txt unreachable), the output is `'true'` (skipped).

## Risks / Trade-offs

- **[Risk] Composition mistakes (wrong jq overlay order, wrong field path) could produce a malformed manifest.** → Mitigation: `validate_config_version` runs *after* compose, against the composed result, before any PR work. A malformed composition is caught at the dedicated gate.

- **[Risk] The base-branch checkout's `version.json` becomes load-bearing on the skip path.** → Mitigation: the base manifest is already required to be schema-valid (`build.yml`'s `validate_version_files` job runs on every PR including merges to main). A carried-forward block is by definition a previously-validated block. Worst case: the schema evolved between the carried-forward block's creation and today, in which case the dedicated validation gate catches it.

- **[Risk] Three more `if:` conditions on the compose step (Android-artifact-present, Windows-artifact-present, test-artifact-present) make the job harder to reason about.** → Acceptable: the conditions are read-once and each guards a single jq overlay. The alternative (always downloading everything, accepting download-step failure as the "absent" signal) is more fragile because actions/download-artifact's behavior on missing artifacts varies by version.

- **[Risk] Renaming `update_android_version`'s artifact (from `version.json` to e.g. `version.json.android`) ripples through any downstream consumer.** → Mitigation: only `validate_config_version` and `update_docs_and_create_pr` consumed it, and both are restructured in this change to consume `composed-manifest` instead. No other workflow downloads this artifact (verified by grep).

- **[Trade-off] One additional job in the workflow graph.** → Acceptable: the new `compose_version_manifest` job is small (one Linux runner, < 30 seconds), and the clarity gain from separating composition from PR creation is worth the visual overhead in the run graph.

- **[Trade-off] Slightly longer overall pipeline (extra job dependency).** → Acceptable: `compose_version_manifest` runs in seconds and is gated by the slower platform-updater jobs anyway, so it doesn't materially extend wall-clock time.

## Automated Test Strategy

- **No new test infrastructure.** All changes are in `.github/workflows/update_version.yml` and one small JavaScript module.
- **Workflow-level**: `validate_config_version` is the dedicated gate. After this change, it validates the composed artifact, so any composition bug is surfaced as a `validate_config_version` failure with a clear CUE error message naming the offending field.
- **End-to-end**: the existing `windows.yml` and `release.yml` image builds and Pester suite continue to assert the manifest-claimed versions actually install on `windows-2025`. Composition mistakes that produce shape-valid but value-wrong manifests would still be caught at the image-test layer.
- **Manual rollout verification**: after merge, trigger `update_version.yml` via `workflow_dispatch` (with Flutter pinned so the gating condition triggers). Confirm: (a) the run graph shows `compose_version_manifest` as a distinct node, (b) `validate_config_version` runs against the composed artifact, (c) the PR body shows annotations consistent with which platforms ran, (d) the resulting `config/version.json` in the PR is byte-equivalent to what today's workflow would have produced (on the happy path).
- **Targeted failure injection during PR review**: as part of the implementation PR, manually disable one platform updater (e.g., set its `if:` to `false`) and trigger a dispatch run; confirm the PR still opens with the carried-forward block and the annotation. Repeat for the other platform.

## Observability

- **Job graph clarity**: the run summary shows a new `compose_version_manifest` job between platform updaters and `validate_config_version`. A skipped Android or Windows job renders the same way it does today; the compose job runs regardless.
- **Per-platform skip signals**: each platform job exposes a `<platform>_skipped` output, surfaced in the PR body annotation when `'true'`. A reviewer can see at a glance which platforms updated this cycle without digging through logs.
- **Validation failures are local**: `validate_config_version` failures now name a single artifact source (`composed-manifest`) rather than a producer-specific one. The error message from `cue vet` already names the offending field path.
- **No silent failures**: the compose job uses `set -euo pipefail` (implicit in `run:` steps); a missing fragment is handled explicitly via `if:` conditions, not by ignoring `jq` errors. The PR job has no error paths that don't propagate to job failure.
- **Forensic artifacts preserved**: `vs-manifests` (channel.json + vsman.json) continues to upload unconditionally from `update_windows_version`, as introduced by `p11`. The composed-manifest artifact adds a second forensic record: the exact `config/version.json` that became the PR's content.

## Migration Plan

- Land as a single workflow PR. No data migration; no schema changes; the committed `config/version.json` on disk is unchanged.
- Rollback is a single revert. Prior behavior (Android as full version.json producer, PR job as composer) returns intact.
- The implementation PR should manually exercise both happy path (`workflow_dispatch` with both platforms running) and skip path (one platform's `if:` temporarily set to `false` during review) to validate the composed artifact looks correct in both modes.

## Open Questions

- None blocking. The fragment shape for Android (whether to include only `.android` or also a defensive `.flutter` from `flutter_version.json` to handle a race) is an implementation detail resolved during the compose-job tasks. The compose step's `jq` expressions are spelled out in tasks.md.
