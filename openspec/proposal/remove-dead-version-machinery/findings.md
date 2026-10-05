# Findings: remove dead version machinery

Research baseline: `f7604a7ce65798491a67df74199027bbcd59b52c`.
The script audit used an independent scout; manifest and workflow tracing were performed inline without isolated research.
These are historical research findings. The final decision preserves the exact-revision test; the version-independent alternative researched in F9 was not adopted.

## F1 — CONFIRMED: The issue calls for three independently removable cleanups

Issue #534 names nine unused scripts, a `cmdlineTools` mirror not consumed as a build argument, and obsolete `30.0.3` job environment entries.
It explicitly asks that call sites be checked again rather than trusting the historical audit.

- <https://github.com/gmeligio/flutter-docker-image/issues/534>

## F2 — REFUTED: Nine current scripts have no repository consumers

The current tree has 19 tracked scripts: 12 have executable consumers and seven have none in current scripts, workflows, Dockerfiles, Compose, mise, docs, or active specs.
An independent audit inspected the seven candidates and found no reusable implementation or dynamic invocation.
External/manual consumers cannot be excluded by repository search.

| Current deletion candidate | Contents |
|---|---|
| [`build_windows.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/build_windows.sh#L1) | CMake configure/build wrapper |
| [`container_structure_test.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/container_structure_test.sh#L1) | One Android structure-test command |
| [`docker_build_android.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/docker_build_android.sh#L1) | Hardcoded Flutter 3.19.0 Docker build |
| [`jq_flutter_latest_version.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/jq_flutter_latest_version.sh#L1) | Stable-release JSON extraction |
| [`test_android_from_linux.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/test_android_from_linux.sh#L1) | Compose and structure-test wrapper |
| [`test_android_from_windows.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/test_android_from_windows.sh#L1) | Compose and structure-test wrapper |
| [`update_changelog.sh`](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/update_changelog.sh#L1) | Hardcoded 3.29.3 changelog command |

- `git ls-files 'script/*'` → 19 paths.
- For each script basename, `git grep -n -F "$basename" -- . ':!openspec/changes/archive' ':!proposal'` → no matches for the seven names above; executable consumers for the other 12.
- `git grep -n -I -E '(script/\*|script/\$|readdir|glob\(|find .*script|for .*script|find script)' -- '**/*' ':!openspec/changes/archive/**'` → no dynamic script execution.
- Representative live consumers: [mise lint](../../../mise.toml#L28), [test generation](../../../.github/workflows/build.yml#L414), [published-image verification](../../../.github/workflows/release.yml#L212), [Linux entrypoint](../../../android.Dockerfile#L83), [Windows test runner](../../../windows.Dockerfile#L147).

## F3 — REFUTED: The cmdlineTools field has no live consumers

`update_test.sh` reads `android.cmdlineTools.version`, constructs version-specific `source.properties` contents, and supplies two CUE tags.
`config/android.cue` rewrites the first file-content test, which currently asserts revision 22.0.
Both PR validation and version-update workflows run the generator.

- [Manifest field](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/config/version.json#L22-L24)
- [Required schema field](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/config/schema.cue#L74)
- [Extraction and tags](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/script/update_test.sh#L9-L26)
- [CUE file-content transformation](https://github.com/gmeligio/flutter-docker-image/blob/f7604a7ce65798491a67df74199027bbcd59b52c/config/android.cue#L67-L76)
- [Generated exact-revision assertion](../../../test/android.yml#L93-L104)
- [PR generation check](../../../.github/workflows/build.yml#L397-L419)
- [Version-update invocation](../../../.github/workflows/update-version.yml#L380)
- `cue export -e android.cmdlineTools.version "$DELTA_SCRATCH_DIR/version-without-cmdline.json"` → `undefined field: cmdlineTools`.
- `cue vet config/schema.cue -d '#Version' "$DELTA_SCRATCH_DIR/version-without-cmdline.json"` → `android.cmdlineTools: field is required but not present`.

## F4 — CONFIRMED: The installed command-line tools revision is not selected by the manifest

The Dockerfile discovers a download URL on Google's Android Studio page, installs it as `cmdline-tools/latest`, and runs `sdkmanager --update`.
Neither the environment exporter nor the shared build action passes a command-line tools revision.
The manifest controls the test's expectation, not the downloaded archive.

- [Dynamic download and update](../../../android.Dockerfile#L172-L206)
- [Manifest-derived exports](../../../script/setEnvironmentVariables.js#L64-L78)
- [Shared Linux build arguments](../../../.github/actions/build-linux-image/action.yml#L78-L86)

## F5 — CONFIRMED: The two stale job defaults do not change exported build arguments

CI and Linux release both invoke the manifest exporter before calling the shared build action.
The exporter always supplies `ANDROID_BUILD_TOOLS_VERSION` from the manifest; the current value is `36.0.0`.
No earlier step references the stale default.

- [CI ordering](../../../.github/workflows/ci.yml#L24-L85)
- [Release ordering](../../../.github/workflows/release.yml#L77-L161)
- [Export](../../../script/setEnvironmentVariables.js#L69)
- [Build-argument consumer](../../../.github/actions/build-linux-image/action.yml#L83)
- Local Node invocation of `setEnvironmentVariables.js`, mocking `core.exportVariable` and asserting all exports equal with and without the initial default →
  `Initial 30.0.3 -> exported ANDROID_BUILD_TOOLS_VERSION=36.0.0`;
  `Initial <absent> -> exported ANDROID_BUILD_TOOLS_VERSION=36.0.0`;
  `All exported values identical with and without stale job default`.

## F6 — CONFIRMED: Existing schema validation and test regeneration pass at the research baseline

Both manifests pass the current CUE schema.
The current Android test generator produces byte-identical output in a scratch copy when run with the project's installed CUE binary.

- [Validation commands](../../../.github/actions/validate-version-manifest/action.yml#L16-L22)
- `cue version` → `cue version v0.17.1`.
- `cue vet config/schema.cue -d '#Version' config/version.json` → exit 0.
- `cue vet config/schema.cue -d '#Images' config/images.json` → exit 0.
- In a scratch copy, `PATH="$(dirname "$(mise which cue)"):$PATH" sh script/update_test.sh`, then `cmp` against the committed test → `Successful baseline test regeneration is byte-identical`.
- Initial scratch execution through the mise shim failed because scratch has no mise version selection; rerunning with the installed binary resolved that environment issue.

## F7 — CONFIRMED: The existing test framework supports version-independent metadata assertions

Container Structure Test 1.22.1 accepts regexes in `expectedContents`.
Its file-content tests fail on a missing file, preserving useful installation coverage without asserting a manually mirrored revision.

- <https://github.com/GoogleContainerTools/container-structure-test/blob/v1.22.1/README.md#file-content-tests>
- [Project-pinned test framework](../../../mise.toml#L8)

## F8 — CONFIRMED: The local environment example still has a live 30.0.3 value

`.env.example` also contains `ANDROID_BUILD_TOOLS_VERSION=30.0.3`, and Compose uses that variable as a build argument.
It is not equivalent to the two overwritten workflow defaults.

- [Environment example](../../../.env.example#L3)
- [Compose consumer](../../../docker-compose.yml#L25-L30)

## F9 — CONFIRMED: Pass-through metadata coverage needs no cmdline-tools tags

A scratch fixture replaced only the first file-content test with one version-independent multiline regex.
Exporting the current CUE command-test transformation with pass-through file-content tests preserved all eight command tests and the analytics test; a second export was identical.
This is a generator feasibility check, not a full execution of the proposed implementation or an image test.

- [Current command-test transformation](../../../config/android.cue#L33-L63)
- [File-content schema](../../../config/android.cue#L15-L19): `expectedContents: [string]` permits exactly one string. An initial three-regex fixture failed with `incompatible list lengths (1 and 3)`; a single multiline regex fits without widening the schema.
- `cue export config/android.cue -l input: "$fixture" -t android_ndk_version=28.2.13676358 -t android_sdk_build_tools_version=36.0.0 -t android_java_version=17 -e '{schemaVersion: output.schemaVersion, commandTests: output.commandTests, fileContentTests: input.fileContentTests}' --out json`, followed by Node deep-equality assertions →
  `No cmdline-tools tags needed: preserved all 8 command tests and 1 other file-content test; repeated export identical`.
- Node regex smoke check, translating the Go multiline flag to JavaScript's `m` flag →
  `Synthetic metadata accepts revisions 22.0, 23.0, 23.0.1; rejects empty metadata and empty revisions`.
