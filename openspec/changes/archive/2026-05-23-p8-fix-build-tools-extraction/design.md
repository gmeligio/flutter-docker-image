## Context

`update_version.yml` builds `config/version.json` from upstream sources across several jobs. `update_android_version` (line ~244) extracts the Android SDK build-tools version from Flutter's `engine/src/flutter/tools/android_sdk/packages.txt`:

```bash
build_tools_version=$(curl -fsSL ".../tags/${FLUTTER_VERSION}/.../packages.txt" \
  | grep 'build-tools' \
  | awk -F'[;:]' '{print $2}')
```

Two upstream realities now break this:

1. Flutter's `packages.txt` (verified against tags `3.41.8` and `3.41.9`) lists multiple build-tools versions on one comma-joined line: `build-tools;36.1.0,build-tools;35.0.0,build-tools;34.0.0,build-tools;33.0.1:build-tools`. Splitting only on `;`/`:` makes `$2 == "36.1.0,build-tools"`.
2. The producer job uploads the resulting `config/version.json` without validating it. The downstream `validate_config_version` job is the first to fail, with a message pointing at the schema, not the extractor.

Older Flutter tags (e.g. `3.35.0`) had a single-version line (`build-tools;36.0.0:build-tools`), which is why the original awk pattern shipped working.

## Goals / Non-Goals

**Goals:**

- Make the extractor produce a clean semver string (`^\d+\.\d+\.\d+$`) regardless of how many `build-tools;X.Y.Z` entries packages.txt lists.
- Surface extractor bugs at the producer job, not three jobs downstream, by adding `cue vet` to `update_android_version` before its artifact upload.
- Keep the change minimal — no schema edits, no gradle changes, no new scripts.

**Non-Goals:**

- Rewriting the extractor in a dedicated script or refactoring `update_version.yml` job structure.
- Changing the upstream source we read from (still `packages.txt` at the Flutter tag).
- Reverse-sorting versions in the workflow — we rely on Flutter's documented ordering (highest first), same as the original implementation.

## Decisions

**Decision: Add `,` to the awk field separator (and anchor grep to start-of-line).**

New line:

```bash
build_tools_version=$(curl -fsSL ".../packages.txt" \
  | grep '^build-tools' \
  | awk -F'[;,:]' '{print $2}')
```

- `grep '^build-tools'` rules out future categories that happen to contain the substring `build-tools` (e.g. a hypothetical `ndk-build-tools;...` line).
- `awk -F'[;,:]'` treats `;`, `,`, and `:` as separators, so on the comma-joined line the second field is the first version (`36.1.0`) — which is Flutter's highest, matching the original behavior on single-version lines.

Alternatives considered:

- **`sed -n 's/^build-tools;\([^,:]*\).*/\1/p'`** — clearer intent, but a larger diff and a different toolchain idiom than the surrounding awk-based steps. Rejected for surface-area reasons.
- **Sort with `sort -V | tail -n1`** — robust to upstream reordering, but adds moving parts for a problem that has never manifested. Flutter has consistently listed highest-first; if that ever changes we can revisit. Rejected as over-engineering.

**Decision: Add `cue vet` to `update_android_version` immediately before `Upload artifact with the updated version.json`.**

`update_windows_version` already does this (line 168–169). Mirroring it gives every producer the same fail-fast guarantee and makes the downstream `validate_config_version` job a defense-in-depth check rather than the primary detector.

Alternatives considered:

- **Validate inside the gradle task** — would require teaching the gradle plugin about CUE or shelling out from gradle. Rejected; the shell-level vet step is simpler and consistent with the rest of the workflow.
- **Add vet *before* the gradle step instead of after** — defeats the purpose; the bad data is written *by* the producer, so we have to vet after the producer step completes.

## Risks / Trade-offs

- **[Risk] Flutter changes ordering in `packages.txt` to lowest-first.** → Mitigation: the new producer-side `cue vet` still catches malformed output. The behavior would shift from "picks highest" to "picks lowest" silently, but both pass the schema. Detection would come from image regressions, not from CI. If this becomes a concern we add `sort -V | tail -n1`, but that's a follow-up.
- **[Risk] Flutter changes the separator again (e.g. moves to YAML).** → Mitigation: the producer-side vet still fails fast and prints the bad value in the log, which makes the next fix obvious. No silent corruption.
- **[Trade-off] Anchoring `grep '^build-tools'` is slightly stricter than the original.** → If Flutter ever prefixes the line (whitespace, a comment marker), the extractor will return empty and the producer-side vet will fail with an unambiguous "missing field" error — louder than today's misleading regex error.

## Automated Test Strategy

- **Level**: workflow-level integration via the scheduled run itself; no new unit-test infrastructure. The change touches only the shell pipeline inside `update_version.yml`.
- **Critical path**: run `update_version.yml` via `workflow_dispatch` against the current Flutter tag (`3.41.9`) and confirm:
  1. `update_android_version` succeeds and its uploaded `version.json` contains `android.buildTools.version == "36.1.0"`.
  2. The new in-job `cue vet` step exits 0 on the well-formed manifest.
  3. `validate_config_version` continues to pass (defense-in-depth).
- **Negative path verification** is local: a one-liner against the real packages.txt confirms the extractor returns exactly `36.1.0`:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/flutter/flutter/refs/tags/3.41.9/engine/src/flutter/tools/android_sdk/packages.txt \
    | grep '^build-tools' | awk -F'[;,:]' '{print $2}'
  # expected: 36.1.0
  ```
- **Regression guard**: the new producer-side `cue vet` is itself the regression test for any future extractor bug — if a producer ever writes a value that doesn't satisfy `#SemverPatch`, the job fails at the producer with a clear pointer.

## Observability

- **Failure surface**: a future bad extraction now fails `update_android_version` directly, with the `cue vet` error referencing `config/version.json` *in the producer job's logs*. The bad value (`echo "Build tools version: $build_tools_version"` already logs at line 246) appears in the same job, two steps above the failure — making the chain trivially diagnosable.
- **No silent failures**: the change converts what was a misleading downstream error ("schema constraint failed at line X") into a producer-local failure. Both `update_windows_version` and `update_flutter_version` already enforce vet at the producer; this brings `update_android_version` to parity.
- **No new logging needed**: the existing `echo "Build tools version: $build_tools_version"` at line 246 is sufficient context once vet fails at the same job. We do not add structured logs because the workflow log is the only sink and is already searchable.

## Migration Plan

- This change is a CI workflow edit only. Deploy by merging the PR; the next scheduled (or manually dispatched) `update_version.yml` run picks it up.
- Rollback: revert the commit. No persistent state changes, no artifacts that need cleanup.
