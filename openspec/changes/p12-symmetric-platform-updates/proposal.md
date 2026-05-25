## Why

`update_version.yml` treats Android and Windows asymmetrically: Android emits the full `config/version.json` (with flutter+android merged in), Windows emits only its block fragment, and the PR job overlays the Windows block onto Android's file. After `p11-resilient-windows-update` made the Windows job soft-skippable, the asymmetry compounded — Windows-job failure no longer blocks the PR but Android-job failure still does. There is no design reason for this; it's a historical accident from the order the platform-update jobs were added.

The composition + validation flow also has the order backwards. Today, `validate_config_version` runs on Android's *partial* output (`flutter`+`android` blocks merged, `windows` block from base branch). The PR job then performs a second composition step (overlaying the new Windows block) and re-validates the merged result. Composition happens on both sides of the validation gate, which means a malformed Windows fragment can only be caught by the PR job's own validate step, not by the dedicated validation job. The single validation gate is no longer load-bearing.

This change normalizes the model: each platform updater emits only its own block as a fragment; a new `compose_version_manifest` job assembles the final `config/version.json` from the base-branch's manifest overlaid with each available fragment; `validate_config_version` runs against the composed result; `update_docs_and_create_pr` becomes a read-only consumer that downloads the validated artifact and opens the PR without touching `config/version.json`. Either Android or Windows skipping is handled identically — the base block carries forward.

## What Changes

- **BREAKING (workflow):** Refactor `update_android_version` to emit a fragment artifact containing only the `android` block changes, not the full `version.json`. The job's logic that fetches Flutter's `packages.txt`, runs Gradle, computes Android tooling versions, and generates `test/android.yml` is unchanged; only the output shape changes.
- Add a `compose_version_manifest` job that runs after both platform updaters. It checks out the base branch (to obtain the committed `version.json` as the composition canvas), downloads whatever fragments are available (Flutter — always; Android — when produced; Windows — when produced), and overlays each block onto the canvas via `jq`. Emits the composed `version.json` as an artifact for downstream consumers.
- Move the Flutter-block overlay (currently done inside Android's job via `script/copyFlutterVersion.js`) into `compose_version_manifest`. The script's environment-variable export (`FLUTTER_VERSION`, `FLUTTER_CHANNEL`) is preserved by calling it from `compose_version_manifest` (and `update_docs_and_create_pr` when it needs those env vars).
- **MODIFIED (workflow):** `validate_config_version` runs against `compose_version_manifest`'s output artifact instead of Android's. It validates the *composed* manifest — the only place where a complete `version.json` exists. Update its `needs:` accordingly.
- **MODIFIED (workflow):** `update_docs_and_create_pr` becomes a read-only consumer. It downloads the validated `config/version.json` from `compose_version_manifest`'s artifact and the `test/android.yml` artifact (if available; falls back to the base-branch checkout's copy when Android skipped). It does *not* run `jq` against `config/version.json`, does *not* re-validate, and does not depend on the individual platform-updater jobs' artifacts.
- Make `update_android_version` soft-skippable on the same model as `update_windows_version`: a job that fails or produces no artifact does not block the PR; the compose job tolerates the missing fragment and the carried-forward base block is used.
- Update the PR body composer to annotate both platforms uniformly: "Android toolchain unchanged this cycle" and/or "Windows toolchain unchanged this cycle", each linking to its job log when applicable.

## Capabilities

### New Capabilities

(none — this change refactors how existing capabilities compose, it doesn't introduce a new one)

### Modified Capabilities

- `flutter-version-update`: the requirement "Upgrade PR contains a coherent, validated `version.json`" is restated for the symmetric model. The PR's `version.json` is the *composed* manifest produced by `compose_version_manifest`; it is validated once, in `validate_config_version`, after composition. Either platform updater (Android or Windows) skipping its update is acceptable — the corresponding block is carried forward unchanged from the base branch. The existing scenarios about build-tools tracking the Flutter tag are preserved (they describe the happy path), and new scenarios cover the Android-skip case alongside the existing Windows-skip case.
- `windows-version-tracking`: the requirement "Monthly upgrade PR includes Windows toolchain updates" is updated to reflect that the Windows job emits a fragment consumed by `compose_version_manifest` (not by `update_docs_and_create_pr` directly). The release-identity check and forensic upload behavior from `p11-resilient-windows-update` are unchanged. The PR job is no longer responsible for merging the Windows block — that responsibility moves to `compose_version_manifest`.

## Impact

- Affected files: `.github/workflows/update_version.yml` (significant restructure of `update_android_version`, new `compose_version_manifest` job, simplification of `update_docs_and_create_pr`). Possibly `script/copyFlutterVersion.js` (no logic change; called from a different job) and `script/setEnvironmentVariables.js` (no logic change; runs against the composed manifest as before).
- No changes to `config/schema.cue`, `config/version.json` (data contract preserved), `windows.Dockerfile`, or any image-build workflow. The composed `version.json` consumed by `update_docs_and_create_pr` is byte-equivalent to today's PR-job-merged result on the happy path.
- Risk: composition mistakes (jq overlay order, missing field) could produce a malformed manifest. Mitigation: the dedicated `validate_config_version` gate sits between composition and PR creation; a malformed composition fails the workflow before any PR opens.
- Risk: the base-branch checkout's `version.json` becomes load-bearing for the skip path (its blocks are carried forward). Mitigation: the base manifest is already required to be schema-valid (enforced by `build.yml`'s `validate_version_files` job on every PR); a carried-forward block is by definition a previously-validated block.
- Relevance gate: this change passes — it modifies the spec-level behavior of two existing capabilities (the composition model and the failure-propagation model are both observable to a CI engineer reviewing the workflow run graph and the PR body annotations). A maintainer reading the spec needs to know that "platform jobs emit fragments, composition is centralized, validation gates the PR".
