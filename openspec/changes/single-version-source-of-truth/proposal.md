## Why

`config/flutter_version.json` duplicates the `flutter` block that already lives in `config/version.json` (channel/commit/version, byte-identical). `version.json` is the manifest every consumer actually reads — `script/setEnvironmentVariables.js` exports `FLUTTER_VERSION` from `data.flutter.version`, and `config/schema.cue`'s `#Version` embeds `#FlutterVersion`, so `version.json` is already schema-complete for Flutter. `flutter_version.json` only ever served two *internal* roles: the change-detection anchor for `update-flutter-version`, and (after `p12-symmetric-platform-updates`) the "Flutter fragment" overlaid in `compose-version-manifest`.

`p12` made `compose-version-manifest` fold `flutter_version.json` into `version.json` and then `rm` it from the generated PR — but left two consumers still requiring the file to exist:

- `build.yml`'s `validate-version-files` job runs `cue vet -d '#FlutterVersion' config/flutter_version.json`, which fails on every auto-generated bump PR once the file is deleted (e.g. PR #496: `stat config/flutter_version.json: no such file or directory`).
- `update-flutter-version` reads its change-detection anchor from `config/flutter_version.json`. Because the automation deletes that file on merge, the *next* scheduled run would read an anchor that no longer exists — a latent self-destruct.

The duplication is the root cause; the broken Build check and the self-destruct are its symptoms. This change finishes the migration `p12` started: make `config/version.json` the single committed source of truth and remove `config/flutter_version.json` entirely, while preserving `p12`'s symmetric model — all three platforms (`flutter`, `android`, `windows`) remain fragment producers overlaid in `compose-version-manifest`.

## What Changes

- **Remove `config/flutter_version.json`** (the committed duplicate) and **`script/copyFlutterVersion.js`** (already dead — no workflow references it; `p12` dropped the call but left the file).
- **MODIFIED (workflow) — `update-flutter-version`:** read the current pinned version from `config/version.json` (`.flutter.version`) instead of `flutter_version.json`. On a bump, overlay the new `flutter` block into the in-job `config/version.json`, validate it, and upload a `{flutter}` fragment (`jq '{flutter}'`) named `version.json.flutter` — symmetric with the Android (`version.json.android`) and Windows (`version.json.windows`) fragment producers. No separate committed file. Expose `flutter_version` / `flutter_channel` scalar outputs for the one mid-pipeline consumer that needs the raw version (`update-android-version`'s `Setup Flutter` step).
- **MODIFIED (workflow) — `compose-version-manifest`:** download and overlay the `version.json.flutter` fragment exactly like the Android and Windows fragments (uniform transport). The Flutter overlay stays unconditional (the pipeline is gated on Flutter having changed), but it travels as a fragment artifact, not a `rm`-and-merge of a committed file.
- **MODIFIED (workflow) — `update-android-version` / `update-windows-version`:** drop the `rm config/flutter_version.json` + `download-artifact` dance tied to the old file. Android reads `FLUTTER_VERSION` / `FLUTTER_CHANNEL` from `update-flutter-version`'s outputs; Windows (which never used the Flutter data) drops the steps outright.
- **MODIFIED (workflow) — `build.yml` `validate-version-files`:** validate only `config/version.json` with `cue vet -d '#Version'`. Since `#Version` embeds `#FlutterVersion`, the `flutter` block (including the stable-channel constraint) is still covered. Remove the `flutter_version.json` line.

## Capabilities

### New Capabilities

(none — this change consolidates the source of truth for an existing capability; it does not introduce a new one)

### Modified Capabilities

- `flutter-version-update`: three requirements are restated to remove the dependency on the deleted `config/flutter_version.json`:
  - **Trigger anchor** — the "new stable Flutter" comparison reads the currently pinned version from `config/version.json` (`.flutter.version`), not `config/flutter_version.json`.
  - **Producer self-validation** — the Flutter producer is now fully symmetric with Android and Windows: it overlays its block into the in-job `config/version.json`, validates the full manifest with `-d '#Version'`, and uploads a `{flutter}` fragment. The previous "Flutter is the exception, validated as a standalone `#FlutterVersion` artifact" carve-out is removed.
  - **Stable-channel enforcement** — the `flutter.channel == "stable"` constraint is unchanged, but it is now enforced via `cue vet -d '#Version' config/version.json` (the constraint lives in `#FlutterVersion`, embedded in `#Version`), not against a standalone `flutter_version.json`.

## Impact

- Affected files: `.github/workflows/update-version.yml` (Flutter producer emits a `{flutter}` fragment; compose overlays it symmetrically; Android/Windows drop the old-file dance), `.github/workflows/build.yml` (`validate-version-files` validates `version.json` only), `config/flutter_version.json` (deleted), `script/copyFlutterVersion.js` (deleted, dead).
- No change to `config/schema.cue` (`#FlutterVersion` stays as a building block of `#Version`), `config/version.json`'s data contract, any image-build workflow (`build.yml` build-args, `windows.yml`, `release.yml`, `prepare-release.yml` all already read `version.json`), or the test suites.
- The auto-generated upgrade PR's `config/version.json` is byte-equivalent to today's composed output on the happy path; the PR simply no longer carries a deletion of `flutter_version.json`.
- A pre-existing branch (`claude/action-failure-root-cause-oh5n25`) already implements an alternative "A1" design that passes the Flutter block via job *outputs* instead of a fragment. This proposal selects the "A2" fragment design to keep all three platforms as uniform fragment producers; implementation adjusts that branch's code from outputs to the `{flutter}` fragment.
- Relevance gate: this change passes — it modifies spec-level behavior of `flutter-version-update` (the trigger anchor and the producer-validation model), both observable to the CI engineer who watches for upgrade PRs and triages failed scheduled runs. It also removes a defect that turns every auto-generated bump PR's Build check red.
