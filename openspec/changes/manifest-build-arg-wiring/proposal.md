## Why

Carrying one value from `config/version.json` to a Docker build costs **five file
edits**: a `core.exportVariable` call in `script/setEnvironmentVariables.js`, plus
a `--build-arg` line in each of four copy-pasted blocks (`build.yml` push path
`:158-164`, `build.yml` fork path `:180-186`, `ci.yml:84-90`,
`release.yml:112-118`).

That cost has already caused a defect. `android.java.version` sits in the manifest
but reaches no build, so the shipped JDK is fixed by hand-typed strings in
`android.Dockerfile` while the manifest merely reports what a previous build
happened to contain. The field was left unwired because wiring it was expensive,
not because it shouldn't be wired.

The four duplicated blocks are also four opportunities to disagree about what was
built. They are kept in sync only by hand.

Relevance gate: this changes observable behaviour a CI engineer depends on — which
versions the published image is actually built with, and whether the four build
legs agree. It also removes the barrier that keeps a manifest field from
influencing the image it describes.

## What Changes

- `script/setEnvironmentVariables.js` gains a single declarative table mapping
  manifest paths to build-argument names, and derives its exports from that table
  instead of eleven hand-written `core.exportVariable` calls.
- The emitter produces one `BUILD_ARGS` value (newline-separated `name=value`
  pairs); the four copy-pasted blocks collapse to
  `build-args: ${{ env.BUILD_ARGS }}`.
- Existing build-argument names are **preserved exactly**. This is a refactor of
  authoring, not of the wire format.

Explicitly **not** a mechanical derivation from the JSON path. The established
names are not derivable: `android.cmake.version` → `cmake_version` drops a
segment, `windows.vsBuildTools.cmakeProject.version` → `vs_cmake_version`
abbreviates two, and `android.ndk.version` → `android_ndk_version` retains the
trailing `version` that a drop-the-suffix rule would remove. A rule that produced
a self-consistent set would rename every `ARG` in both Dockerfiles for no user
benefit. The honest artifact is a table.

Not in scope, and stated so it is not mistaken for an omission: the Windows image
build (it hand-assembles a PowerShell array rather than using
`docker/build-push-action`, so it needs a different shape); renaming any existing
build argument; and moving the nine Renovate-owned apt pins into the manifest.

## Capabilities

### New Capabilities

- `manifest-build-arg-wiring`: how `config/version.json` fields reach the Docker
  build — the declared name mapping, the single emission point, and the per-ARG
  granularity that keeps layer caching intact.

## Impact

**Modified**: `script/setEnvironmentVariables.js` (table-driven emitter +
`BUILD_ARGS`); `.github/workflows/build.yml` (two build-arg blocks),
`.github/workflows/ci.yml`, `.github/workflows/release.yml` (one each).

**Unchanged by design**: every build-argument name and value; every `ARG`
declaration in `android.Dockerfile` and `windows.Dockerfile`;
`config/version.json` itself; `windows-image.yml`.

**Verification**: the emitted `--build-arg` set must be byte-identical to the
current one. Because no name or value changes, a diff of the resolved
`docker buildx build` command line before and after is a complete check.

**Risk**: `BUILD_ARGS` makes the four call sites opaque — a reader no longer sees
which arguments are passed. Mitigated by the job log printing the resolved value
and by the table being a single readable list. Net legibility improves: one
authoritative list replaces four hand-synced copies.

**Enables**: wiring `android.java.version` through to the image
(`flutter-java-version-derivation`), which is blocked on this cost today. That
change depends on this one only for convenience — it can declare its own ARG
either way.
