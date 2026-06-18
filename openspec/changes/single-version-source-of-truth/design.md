## Context

`p12-symmetric-platform-updates` established the model that `update-version.yml` uses today: each platform updater writes its block, validates, and uploads a fragment artifact; `compose-version-manifest` overlays the fragments onto the schema-valid base `config/version.json`; `validate-config-version` gates the composed result; `update-docs-and-create-pr` is a read-only consumer.

`p12`'s design treated Flutter as a fragment producer "for symmetry" but implemented that fragment as the committed file `config/flutter_version.json` — a file that *duplicates* `config/version.json`'s `flutter` block. The compose step folds that file into `version.json` and `rm`s it. Two facts make this load-bearing-wrong:

1. The committed `config/flutter_version.json` is redundant with `config/version.json`'s `flutter` block. Nothing outside the update pipeline reads it (`script/setEnvironmentVariables.js` reads `version.json`; `#Version` embeds `#FlutterVersion`).
2. The pipeline both *requires* the file (trigger anchor in `update-flutter-version`; `cue vet` in `build.yml`) and *deletes* it (in compose, from the PR). On merge, `main` loses the file the next run depends on.

```
  TODAY (broken)
  update-flutter-version ── reads/writes ──▶ config/flutter_version.json (committed duplicate)
        │ upload artifact                              │
  compose ── overlay flutter ──▶ rm flutter_version.json  ← PR deletes it
        │
  build.yml: cue vet -d '#FlutterVersion' config/flutter_version.json  ← RED after delete
```

This change keeps `p12`'s symmetric fragment model but sources the Flutter fragment from `config/version.json` and deletes the duplicate file.

## Goals / Non-Goals

**Goals:**

- `config/version.json` is the single committed source of truth for the Flutter version. No second committed file holds the same data.
- Preserve `p12` symmetry: `flutter`, `android`, and `windows` are all fragment producers (`version.json.<platform>`), each overlaid in `compose-version-manifest`.
- Remove the self-destruct: no workflow step deletes a file that a later run depends on.
- `build.yml`'s `validate-version-files` validates the single manifest and still covers the Flutter block (including the stable-channel constraint).

**Non-Goals:**

- Changing `config/schema.cue` or any per-platform extractor logic (Flutter release resolution, Android `packages.txt`/Gradle, Windows vsman identity-matching are unchanged).
- Removing the `compose-version-manifest` / `validate-config-version` / `update-docs-and-create-pr` job structure.
- Changing the committed `config/version.json` schema or its happy-path byte output.
- Adopting the alternative "A1" design (Flutter via job outputs, no fragment). A1 is simpler but asymmetric; this change deliberately chooses the uniform fragment model.

## Decisions

### Decision: The Flutter fragment is derived from `config/version.json`, not a separate committed file

`update-flutter-version` resolves the latest stable release, compares against `config/version.json`'s `.flutter.version`, and on a bump overlays the new `flutter` block into the in-job `config/version.json`:

```sh
jq --arg channel "$c" --arg commit "$h" --arg version "$v" \
   '.flutter = {channel: $channel, commit: $commit, version: $version}' \
   config/version.json > tmp && mv tmp config/version.json
```

It then stages the fragment with `jq '{flutter}' config/version.json > "$RUNNER_TEMP/version.json.flutter"` and uploads it as `version.json.flutter`. This makes Flutter structurally identical to the Android (`jq '{android, fastlane}'`) and Windows (`{windows}`) producers.

Alternatives considered:

- **Keep `config/flutter_version.json` as the committed fragment (revert p12's `rm`).** Rejected: reinstates the duplication that is the root cause.
- **Pass the Flutter block via job outputs, no fragment (the "A1" design on the existing branch).** Rejected for this change: simplest in isolation, but introduces a second transport mechanism (outputs for Flutter, artifacts for Android/Windows) and diverges from the `p12` fragment model a future maintainer would reasonably expect to extend. A2 keeps one pattern.

### Decision: Scalar `flutter_version` / `flutter_channel` outputs serve the one mid-pipeline consumer

`update-android-version`'s `Setup Flutter` and Gradle steps need the *new* Flutter version/channel before the manifest is composed. Rather than have Android download and parse the `version.json.flutter` fragment (re-introducing a download step), `update-flutter-version` also exposes `flutter_version` and `flutter_channel` as job outputs. Android reads them directly into `$GITHUB_ENV`.

This is a deliberate split, not a contradiction of the fragment model: the **fragment** is the manifest-composition transport (consumed by `compose-version-manifest`); the **scalar outputs** are a convenience for a consumer that needs the raw version string mid-pipeline. Android does not need the structured block, so it does not download the fragment.

### Decision: Flutter producer validates the full in-job `#Version` manifest, like the others

Because `update-flutter-version` now overlays its block into `config/version.json`, it validates the full in-job manifest with `cue vet config/schema.cue -d '#Version' config/version.json` — identical to the Android and Windows producers. This removes `p12`'s "Flutter is the exception, validated as a standalone `#FlutterVersion` artifact" carve-out. `#FlutterVersion` remains a building block of `#Version` (so the stable-channel constraint still applies); it is simply no longer invoked against a standalone file.

### Decision: `compose-version-manifest` overlays the Flutter fragment unconditionally

The compose job downloads `version.json.flutter` (always present — the pipeline is gated on Flutter having changed) alongside the conditionally-present Android and Windows fragments, and overlays it onto the base manifest. The Flutter fragment id is prepended to the existing dynamic artifact-id list; the per-fragment overlay is guarded by file presence for Android/Windows and unconditional for Flutter. The `rm config/flutter_version.json` step is deleted.

### Decision: `build.yml` validates only `config/version.json`

`validate-version-files` runs `cue vet config/schema.cue -d '#Version' config/version.json`. The `-d '#FlutterVersion' config/flutter_version.json` line is removed; its coverage is subsumed because `#Version` embeds `#FlutterVersion`.

```
  AFTER (A2)
  update-flutter-version ── overlay into version.json ──▶ upload {flutter} fragment
        │  (+ flutter_version/channel outputs)                     │
  update-android/windows ── upload {android}/{windows} fragments   │
        │                                                          ▼
  compose ── overlay flutter (uncond.) + android/windows (guarded) onto base version.json
        │
  validate-config-version ── cue vet -d '#Version' ──▶ update-docs-and-create-pr (read-only)

  config/version.json = SINGLE source of truth; no flutter_version.json; nothing self-deletes
```

## Automated Test Strategy

This capability has no unit-test harness; it is verified by the workflows themselves and by a manual dry-run:

- **Critical path — schema validity:** `cue vet config/schema.cue -d '#Version' config/version.json` must pass for the committed manifest (`build.yml` `validate-version-files`) and for the composed manifest (`update-version.yml` `validate-config-version`). Both gates already exist; this change only removes the redundant `-d '#FlutterVersion' config/flutter_version.json` invocation.
- **Producer self-validation:** each producer (now including Flutter) runs `cue vet -d '#Version'` on its in-job manifest before upload, failing fast at the offending job.
- **Manifest-shape assertions (local, pre-merge):** confirm `jq '{flutter}' config/version.json` produces a `#FlutterVersion`-shaped document and that the compose overlay `jq '.flutter = {...}'` preserves the `android`, `fastlane`, and `windows` blocks. These can be run by hand against the committed `version.json` without CI.
- **End-to-end:** a `workflow_dispatch` run of `update-version.yml` (or the next scheduled run) must open an upgrade PR whose `config/version.json` is byte-equivalent to today's happy-path output and whose diff contains **no** deletion of `config/flutter_version.json`. The PR's own `build.yml` Build check must pass `validate-version-files`.

## Observability

- **Producer failures are loud and located:** each producer's `cue vet -d '#Version'` step fails its own job (red in the Actions tab) at the step that produced the bad block, before any artifact upload — no silent propagation to a downstream compose failure.
- **Composition/validation gate:** `validate-config-version` fails the workflow before `update-docs-and-create-pr` runs, so a malformed composed manifest blocks the PR rather than opening a bad one.
- **Trigger transparency:** `update-flutter-version` logs the current pinned version (read from `config/version.json`) and the resolved upstream version, so a "no change" green run and a "bump detected" run are distinguishable in the log.
- **No silent self-destruct:** the failure mode this change eliminates (a deleted anchor file surfacing only on the *next* run) is removed by construction — there is one committed file and no step deletes it. The previously-failing `build.yml` `validate-version-files` becomes a positive signal again.
- **Regression guard:** `build.yml`'s `validate-version-files` runs on every PR including merges to `main`, so any future reintroduction of a non-schema-valid or duplicated Flutter source surfaces as a red Build check on the introducing PR.
