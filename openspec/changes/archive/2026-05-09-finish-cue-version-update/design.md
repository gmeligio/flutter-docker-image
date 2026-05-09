## Context

`update_version.yml` is a four-job pipeline:

```
update_flutter_version  →  update_android_version  →  validate_config_version  →  update_docs_and_create_pr
       (host)                  (container)                   (host)                    (host)
```

Job 1 decides "is there a new Flutter?" and emits an artifact + a `result` step output. Every later job is gated by `if: needs.update_flutter_version.outputs.new_version == 'true'` directly or transitively.

Today on `single_update`, job 1 runs two overlapping steps:

1. A **new** CUE step (`Fetch and update latest Flutter version`) that fetches `releases_linux.json`, runs `cue import` + `cue eval --force --outfile config/flutter_version.json`. It does NOT compare or set any output.
2. The **old** github-script step (`Update latest Flutter version`) that reads `config/flutter_version.json` from disk, fetches the same JSON, compares against the on-disk version, returns `true`/`false`.

Because the new step writes the file before the old step reads it, the old step always sees no diff and returns `false`. The pipeline becomes a permanent no-op.

Constraints:

- The workflow must keep using `actions-version-tracking` pins (gx) — every `uses:` is SHA-pinned and version-tracked in `.github/gx.toml`. New `uses:` lines (none planned) would need a manifest entry.
- `cue@0.15.0` is already installed in the workflow via `jaxxstorm/action-install-gh-release` — reuse that.
- The existing `script/copyFlutterVersion.js` runs in job 2 inside the `flutter-android` container and merges the `flutter` sub-document into the larger `version.json`. It's orthogonal to job 1 and stays.

## Goals / Non-Goals

**Goals:**

- Job 1 reaches "new version available" → `result == 'true'` → downstream jobs run, exactly when the upstream stable version changes.
- The Android `buildTools` version in `version.json` is sourced from Flutter's `packages.txt` for the new tag, replacing the current orphan curl step with a wired-in value consumed by the CUE `version.json` generator.
- `cue vet` passes against the committed `config/flutter_version.json` and against any `version.json` produced by the workflow.
- `script/updateFlutterVersion.js` is deleted (the goal of the branch — single CUE-driven flow).

**Non-Goals:**

- Rewriting `script/copyFlutterVersion.js` into CUE. It's tangential and works.
- Replacing the github-script step in job 2 that updates the Fastlane version (`updateFastlaneVersion.js`) — separate concern.
- Restructuring the four-job pipeline. Same job names, same `needs:` graph, same artifact handoffs.
- Changing the cron schedule.
- Anything related to the docs build in job 4.

## Decisions

### Decision 1: Replace JS with one shell+CUE step, not a multi-step CUE pipeline

The new job-1 step does the full read-old / fetch / compare / conditionally-write / set-output sequence in one bash block, calling `cue` for the heavy lifting (parsing JSON, pulling fields, writing the new file). Rationale: keeping it in one step keeps the `result` output local and avoids an inter-step file-handoff dance. CUE is used where it adds value (typed JSON manipulation, schema validation) and bash is used where it's natural (HTTP, comparison, `$GITHUB_OUTPUT`). A pure-CUE pipeline would need a wrapper script anyway.

Alternative considered: split into 4 steps mirroring the inline TODO comments. Rejected — every split needs an artifact or `$GITHUB_OUTPUT` plumbing for the next step, with no real benefit.

### Decision 2: Source build-tools version with a CUE-aware shell step in job 2

The build-tools version comes from `https://raw.githubusercontent.com/flutter/flutter/refs/tags/<FLUTTER_VERSION>/engine/src/flutter/tools/android_sdk/packages.txt`. The current orphan step already does the curl+awk extraction. We give it an `id`, write to `$GITHUB_OUTPUT`, then plumb the value into the existing `script/update_test.sh` / CUE `version.json` generation path so it lands in `config/version.json`.

Open implementation question (Open Question 1): the current `update_test.sh` derives `android_sdk_build_tools_version` from gradle output via `updateAndroidVersions.gradle.kts`. We need to choose whether `packages.txt` *replaces* the gradle source or *cross-checks* it. Default: replace, since `packages.txt` is the upstream source of truth Flutter itself uses.

Alternative considered: query the gradle plugin only and trust it. Rejected — the user explicitly asked for `packages.txt` as the source.

### Decision 3: Channel restricted to `"stable"` in the schema

`config/schema.cue#FlutterVersion.flutter.channel` becomes literal `"stable"` (not a disjunction). Rationale: the fetcher already filters by `^\d+\.\d+\.\d+$`, which stable-only releases match. The schema change makes that invariant explicit and rejects accidental beta/dev pins at validation time.

Alternative considered: keep `"stable" | "beta"`. Rejected — user confirmed stable-only is intentional.

### Decision 4: Keep `script/copyFlutterVersion.js`, delete `script/updateFlutterVersion.js`

Only the **fetch + compare** is migrating to CUE. The merge of `flutter_version.json` into `version.json` (job 2 step) stays as-is. Rationale: scope. The branch's goal as named (`single_update`) is the fetch path; broadening scope to also rewrite the merge would multiply the change surface for no user-visible benefit.

### Decision 5: Output `result` as a step output, not a job output value derived from artifact presence

The old job-2 `if:` gate reads `needs.update_flutter_version.outputs.new_version`, which today maps to `steps.update_flutter_version.outputs.result`. Keep the same shape: the new step has `id: update_flutter_version` and writes `result=true|false` to `$GITHUB_OUTPUT`. Job-level outputs and downstream `if:` conditions remain literally unchanged.

Alternative considered: replace `result` with "did we upload the artifact" — rejected, would touch every downstream `if:` for no gain.

## Risks / Trade-offs

- **[Risk] `cue import` output shape may not expose `releases` as a top-level field.** `cue import file.json` produces a CUE file whose top-level fields mirror the JSON's top-level keys. `releases_linux.json`'s top level is `{"base_url": ..., "current_release": {...}, "releases": [...] }`, so `releases[0].channel` should resolve. Could not verify live (sandbox network timeouts to googleapis). → **Mitigation:** the implementation step runs `cue eval` with a smoke value and a fallback to `--list` mode; if the shape is different, implementer iterates locally with `mise use cue@0.15.0`.

- **[Risk] `packages.txt` format changes.** A future Flutter version could split `build-tools` into multiple lines or change the `;` delimiter. Today: `grep 'build-tools' | awk -F'[;:]' '{print $2}'`. → **Mitigation:** if the extraction returns empty or a non-semver string, the CUE schema (`buildTools!: #SemverPatch`) rejects it at the `validate_config_version` job, failing loudly rather than silently shipping a bad image.

- **[Risk] First post-merge run produces a large PR (potentially several Flutter versions worth of catch-up).** The repo has been unable to bump versions while this branch was broken. → **Mitigation:** none needed — that's the desired behavior; the maintainer reviews and merges as normal.

- **[Trade-off] CUE installed twice in the workflow (job 1 host, job 2 container) and shell logic in job 1.** The job-2 install is unavoidable (different runner). Bash-glue in job 1 is a small cost for keeping `result` plumbing colocated.

## Automated Test Strategy

Manual + CI:

- Local: `cue vet config/schema.cue -d '#FlutterVersion' config/flutter_version.json` (run via `mise use cue@0.15.0`). Today fails (`#PatchVersion`); after the fix it must pass.
- Local: `cue vet config/schema.cue -d '#Version' config/version.json` against the committed `config/version.json`. Must pass after the channel narrowing.
- Local dry-run of the new fetch step as a shell script against a checked-in fixture of `releases_linux.json` to assert (a) when the fixture's latest stable matches the on-disk version, the script writes `result=false` and does NOT modify `config/flutter_version.json`; (b) when they differ, it writes `result=true` and overwrites the file with a `cue vet`-passing payload.
- CI: trigger `update_version.yml` via `workflow_dispatch` on the branch before merge. Two trigger paths to exercise: (i) immediately, expecting either `true`-path-to-PR or `false`-path-to-clean-skip depending on whether main is current; (ii) after artificially rewinding `config/flutter_version.json` to an older version on the branch, expecting `true` path through to PR creation.
- Critical path under test: job-1 step output → job-2 gate → `validate_config_version` `cue vet` → job-4 PR title/commit message non-empty.
- No new test infrastructure required.

## Observability

- The new fetch step `echo`s the old version, the new version, and the comparison verdict before writing `$GITHUB_OUTPUT`. Visible in the run log without enabling debug logging.
- `cue vet` failures produce explicit constraint-violation messages (already true in `build.yml` and `validate_config_version`).
- The `Create commit message variable` step bug (writes to wrong file) is silent today — empty PR title masks the symptom. After the fix, the step echoes the resolved value, and an empty value would surface as a PR-creation step error rather than a silently-wrong PR.
- Failure modes that must NOT be silent:
  - Fetch failure → step exits non-zero (no `set +e`), job goes red.
  - Empty/non-semver build-tools extraction → CUE schema rejects in `validate_config_version`, downstream PR job is skipped, run is red.
  - Schema reference errors → caught at `cue vet` in either `build.yml` or `validate_config_version`.

## Migration Plan

This is a workflow + schema change with no runtime/image surface, so "deploy" = merge to `main`.

1. Land the change on `single_update`, push to GitHub.
2. Trigger `update_version.yml` via `workflow_dispatch` on the branch.
3. If green and either (a) PR opened against the branch, or (b) clean skip after job 1 — merge to main.
4. First scheduled run after merge produces a real upgrade PR (or skips cleanly if main is already current).

**Rollback:** revert the merge commit. Workflow returns to the pre-`single_update` JS-based fetch — known-working state.

## Open Questions

1. **Build-tools sourcing:** does `packages.txt` *replace* or *cross-check* the gradle-plugin extraction in `updateAndroidVersions.gradle.kts`? Default is replace, but `update_test.sh` and the gradle script may need to be adapted in the same change. To confirm during implementation by reading `script/update_test.sh` and the gradle script.
