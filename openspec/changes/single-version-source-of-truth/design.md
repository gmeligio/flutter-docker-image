## Context

`p12-symmetric-platform-updates` gave `update-version.yml` a fragment-artifact pipeline: each platform updater writes its block, validates, and uploads a fragment artifact; `compose-version-manifest` downloads the fragments and overlays them onto the base `config/version.json`; `validate-config-version` gates the composed result; `update-docs-and-create-pr` is a read-only consumer.

Two facts make that machinery heavier than it needs to be:

1. **The version data is tiny and scalar.** Each cycle's new values are a handful of strings/ints per platform — well within job-output limits. `p12` used artifacts on the reasoning that "outputs are size-limited, not for structured data", but that does not bind here.
2. **`test/android.yml` is derived, not authored.** `script/update_test.sh` regenerates it from `config/version.json` via `cue export config/android.cue` (`script/update_test.sh:11-25`), taking the committed `test/android.yml` as the structural input and overlaying version values. Any job holding the composed manifest can rebuild it; it never needs to cross a job boundary as an artifact.

`config/flutter_version.json` is also a committed *duplicate* of `version.json`'s `flutter` block, which `p12` deletes from the PR while other steps still require it — breaking `build.yml`'s Build check and leaving a self-destructing trigger.

```
  TODAY (p12) — 7 jobs, ~4 version artifacts
  flutter/android/windows ──stage→upload fragment──▶ compose ──download→merge→overlay──▶ validate ──▶ PR
        │ (flutter fragment == committed flutter_version.json, rm'd in compose)
        └ android also uploads test/android.yml
```

## Goals / Non-Goals

**Goals:**

- `config/version.json` is the single committed source of truth; no second committed file holds the same data.
- Remove the version-artifact subsystem: producers report blocks as job outputs; no `upload-artifact`/`download-artifact`/id-list/`merge-multiple`/`rm`-overwrite plumbing for version data.
- `test/android.yml` is regenerated from the composed manifest, so it cannot drift from `version.json`.
- One composition + one validation gate, in one job, before the PR is opened.
- Preserve producer self-validation (a malformed block fails *its* producer job, not a downstream gate) and the carry-forward behavior for skipped platforms.

**Non-Goals:**

- Changing `config/schema.cue`, the Flutter/Android/Windows resolution logic, `script/update_test.sh`, or `config/android.cue`.
- Changing `config/version.json`'s committed role, schema, or happy-path byte output.
- Touching image-build workflows (`build.yml` build path, `windows.yml`, `release.yml`, `prepare-release.yml`) or test suites.
- Removing the Windows `vs-manifests` forensic artifact (independent of the version data flow).

## Decisions

### Decision: Producers report their block as a job output

Each producer overlays its block onto its in-job checkout of `config/version.json`, validates with `cue vet config/schema.cue -d '#Version' config/version.json` (its block on the schema-valid base → a passing `#Version` confirms the block), then emits the block as a compact JSON job output:

- `update-flutter-version` → outputs `changed`, `flutter_channel`, `flutter_commit`, `flutter_version` (the Flutter overlay is trivial; the scalars also feed the Android job directly).
- `update-android-version` → `android_block = $(jq -c '{android, fastlane}' config/version.json)`, plus `android_skipped`.
- `update-windows-version` → `windows_block = $(jq -c '{windows}' config/version.json)` when the release-identity check matches, else empty, plus `windows_skipped`.

For Android and Windows this is a *small* change — they already overlay-and-validate today; only the final "stage file + upload-artifact" becomes "echo block to `$GITHUB_OUTPUT`".

Alternatives considered:
- **Keep fragment artifacts (the A2 design).** Rejected: preserves the artifact boilerplate that is the actual maintenance cost; buys only downloadable forensics (the PR already carries the exact manifest).
- **Pass full `version.json` from each producer as an output.** Rejected: forces a 3-way merge and obscures which block each producer owns. Per-block outputs keep ownership explicit.

### Decision: `test/android.yml` is regenerated downstream, not shipped

The Android job stops generating and uploading `test/android.yml`. The final job runs `script/update_test.sh` against the *composed* `config/version.json` (with the base `test/android.yml` from checkout as the structural input). On the Android-skip path the composed manifest carries the base `android` block, so regeneration reproduces the base `test/android.yml` byte-for-byte — no special-casing.

### Decision: Collapse compose + validate + PR into one job

`compose-version-manifest` and `validate-config-version` are removed. The final job `compose-and-open-pr` (renamed from `update-docs-and-create-pr`):

1. Checks out the base branch (`fetch-depth: 0`, `fetch-tags: true` for the changelog) — the schema-valid base `version.json` is the composition canvas.
2. Overlays the platform blocks from job outputs (passed via `env:`, not inline interpolation):
   ```sh
   jq --arg channel "$FLUTTER_CHANNEL" --arg commit "$FLUTTER_COMMIT" --arg version "$FLUTTER_VERSION" \
      '.flutter = {channel: $channel, commit: $commit, version: $version}' config/version.json > t && mv t config/version.json
   [ -n "$ANDROID_BLOCK" ]  && jq --argjson a "$ANDROID_BLOCK"  '. + $a' config/version.json > t && mv t config/version.json
   [ -n "$WINDOWS_BLOCK" ]  && jq --argjson w "$WINDOWS_BLOCK"  '. + $w' config/version.json > t && mv t config/version.json
   ```
   Flutter is unconditional (the pipeline is gated on Flutter changing); Android/Windows are guarded on a non-empty block output, else the base block carries forward.
3. Regenerates `test/android.yml` via `script/update_test.sh`.
4. Validates the composed manifest: `cue vet config/schema.cue -d '#Version' config/version.json` — the single central gate, as a step. `bash -e`/step failure stops the job before any PR step runs.
5. Exports env vars (`setEnvironmentVariables.js`), builds docs (`mise run docs`), generates the changelog (`git-cliff`), composes the PR body with per-platform "unchanged this cycle" annotations (from `android_skipped`/`windows_skipped`), and opens the PR.

The single-gate property is now *real* (composition and validation are adjacent in one job, validation strictly before PR creation), and a failing **step** still identifies compose-vs-validate-vs-PR in the log without needing separate jobs.

Alternatives considered:
- **Keep `validate-config-version` as a separate job (the Hybrid).** Rejected for this change: without an artifact to hand off, a separate validate job would need to re-receive the composed manifest (re-introducing an artifact). Co-locating compose+validate removes that need; step-level granularity preserves log clarity.

### Decision: `build.yml` validates only `config/version.json`

`validate-version-files` runs `cue vet config/schema.cue -d '#Version' config/version.json`. The `-d '#FlutterVersion' config/flutter_version.json` line is removed; `#Version` embeds `#FlutterVersion`, so the `flutter` block and its `channel: "stable"` constraint stay covered.

```
  AFTER (C) — 5 jobs, 0 version artifacts
  setup ─▶ update-flutter-version ─(outputs)─┐
                 │ (changed gate)             │
          update-windows-version ─(windows_block output)─┤
          update-android-version ─(android_block output)─┤
                                                          ▼
                          compose-and-open-pr: overlay outputs → regen android.yml
                                                → cue vet (#Version) → docs → PR
  config/version.json = SINGLE committed source of truth; no flutter_version.json
```

## Automated Test Strategy

No unit-test harness exists; verification is by the workflows plus a manual dry-run:

- **Schema gate (critical path):** `cue vet -d '#Version' config/version.json` must pass for the committed manifest (`build.yml` `validate-version-files`) and for the composed manifest (the gating step in `compose-and-open-pr`).
- **Producer self-validation:** each producer runs `cue vet -d '#Version'` on its in-job manifest before emitting its block output, so a malformed block fails the producer job.
- **Local shape checks (pre-merge, no CI):** `jq -c '{android, fastlane}' config/version.json` and `jq -c '{windows}' config/version.json` produce valid block JSON; the overlay chain (`jq --arg` flutter, `jq --argjson` android/windows) preserves all sibling blocks; `script/update_test.sh` regenerates `test/android.yml` byte-identically from the committed manifest.
- **End-to-end:** a `workflow_dispatch` (or scheduled) run opens an upgrade PR whose `config/version.json` and `test/android.yml` are byte-equivalent to today's happy-path output, whose diff contains **no** deletion of `config/flutter_version.json`, and whose `build.yml` `validate-version-files` check passes. Validate the Android-skip and Windows-skip paths by confirming the corresponding base block (and regenerated `test/android.yml`) carries forward and the PR body annotation appears.

## Observability

- **Producer failures are loud and located:** each producer's `cue vet -d '#Version'` fails its own job at the offending step, before its block output is emitted — no silent propagation.
- **Central gate before PR:** the `cue vet` step in `compose-and-open-pr` runs strictly before the PR-creation step; a malformed composed manifest fails the run with a red job and no PR opened. Compose-vs-validate-vs-PR are distinguishable by which step failed.
- **Skip transparency:** an empty `android_block`/`windows_block` output drives both the carry-forward overlay and the PR-body "toolchain unchanged this cycle" annotation, so a reviewer sees which platforms moved without reading job logs.
- **Trigger transparency:** `update-flutter-version` logs the pinned version (from `config/version.json`) vs the resolved upstream version, distinguishing a green "no change" run from a "bump detected" run.
- **No silent self-destruct:** with one committed file and no step that deletes it, the failure mode where a deleted anchor surfaces only on the *next* run is removed by construction; `build.yml` `validate-version-files` returns to a positive signal and guards against any future reintroduction of a duplicated/non-schema-valid Flutter source on the introducing PR.
