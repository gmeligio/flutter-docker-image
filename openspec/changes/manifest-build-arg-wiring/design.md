## Context

`script/setEnvironmentVariables.js` hand-lists eleven `core.exportVariable` calls;
four workflow files each restate the same six `--build-arg` lines. Adding one
manifest value means touching five files. Full findings in
`../loud-deb-pin-resolution/research.md` (F10).

## Goals / Non-Goals

**Goals:**

- Adding a manifest value costs one table row plus one `ARG`, not five file edits.
- The four Linux build legs read one authoritative list and cannot drift.
- Per-ARG Docker layer-cache granularity is preserved exactly.
- Zero change to emitted build-argument names and values.

**Non-Goals:**

- Renaming any build argument.
- The Windows image build (`windows-image.yml:130-149` assembles a PowerShell
  array, not a `build-args:` block).
- Moving the nine Renovate-owned apt pins into `config/version.json`.

## Decisions

### D1 — A declared table, not a derivation rule

The first design of this change specified mechanical derivation from the JSON path
(lowercase, underscore-separate, drop a trailing `.version`/`.build`). Checking it
against the eleven names actually in use showed it cannot work:

| Manifest path | Actual ARG | Why no rule produces it |
|---|---|---|
| `android.ndk.version` | `android_ndk_version` | retains `version` |
| `android.cmake.version` | `cmake_version` | drops the `android` segment |
| `windows.git.version` | `git_version` | drops the `windows` segment |
| `windows.vsBuildTools.cmakeProject.version` | `vs_cmake_version` | abbreviates two segments, retains `version` |
| `windows.vsBuildTools.windows11Sdk.build` | `vs_win11sdk_build` | abbreviates two segments, retains `build` |
| `android.platforms` | `android_platform_versions` | array → space-joined string |

Any single rule contradicts at least half of these. A rule that produced a
self-consistent set would rename every `ARG` in both Dockerfiles — a coordinated
multi-file change that no consumer of the image benefits from.

So the table *is* the specification. It is smaller than the eleven hand-written
export calls it replaces, every exception is visible in one place rather than
implied by its absence, and it makes the "one row per value" cost explicit.

### D2 — `BUILD_ARGS` as newline-separated pairs, not a serialized manifest

`docker/build-push-action`'s `build-args:` input is already newline-separated
`name=value`, so emitting that exact shape means the four call sites become
`build-args: ${{ env.BUILD_ARGS }}` with no other change.

**Layer caching is the constraint that shapes this.** The tempting simplification —
one JSON build-arg, or `COPY config/version.json` into the build — would make any
version change invalidate every layer below it. Builds run 15–25 minutes and lean
on registry buildcache (`build.yml:151-152`), so a Fastlane bump must not re-clone
the Flutter SDK. Emitting N pairs keeps BuildKit seeing N distinct build-args
exactly as today. Only *authoring* is centralized; the wire format is unchanged.

### D3 — Non-manifest exports keep their own names

`FLUTTER_VERSION` is read by tagging and test steps, not only by the build.
`IMAGE_REPOSITORY_PATH` is composed from `GITHUB_REPOSITORY_OWNER` and
`IMAGE_REPOSITORY_NAME` and never appears in the manifest at all. Both continue
to be exported individually. `BUILD_ARGS` covers manifest-derived build arguments;
it is not a replacement for the environment.

## Automated Test Strategy

The change is a pure refactor with a complete, cheap check: **the resolved
`docker buildx build` command line must be byte-identical before and after.**

1. Capture the current `--build-arg` set from a recent CI run's build step
   (run `31194164846` shows the present form).
2. After the refactor, compare the same line from a PR run — same names, same
   values, same count.

Because no name or value changes, that diff is exhaustive; no new test
infrastructure is warranted. The existing `container-structure-test` legs
(`test/android.yml`) remain the backstop that the built image is correct.

## Observability

| Failure | Surfaces as |
|---|---|
| Table omits a value a Dockerfile declares | Empty `ARG` → build fails at the consuming `RUN` |
| Table names a path absent from the manifest | Emitter throws → the step fails before any build starts |
| `BUILD_ARGS` malformed (missing `=`) | `docker/build-push-action` rejects the input |
| A workflow still restates args inline | Caught in review; the delta forbids it |

**Logging**: the emitter should print the resolved `BUILD_ARGS` so a job log shows
exactly what was passed. This is what preserves legibility once the four call
sites stop listing arguments individually.

**Cannot fail silently**: a missing build argument becomes an empty `ARG`, and
every current consumer uses its value in a `RUN` that fails without it.

## Risks / Trade-offs

**[`BUILD_ARGS` is opaque at the call site]** → Four workflow files no longer show
which arguments are passed. Mitigated by logging the resolved value and by the
table being one readable list. Net legibility improves: four hand-synced copies
become one authoritative list.

**[The table is still hand-maintained]** → It is, and deliberately. The
alternative is a rule that renames every `ARG`. One row per value, in one file, is
the honest floor for this manifest.

**[Refactor touches four workflow files at once]** → Unavoidable, since the point
is removing duplication. Bounded by the byte-identical check: if the emitted set
matches, the refactor is correct.

## Migration Plan

1. Add the table and `BUILD_ARGS` emission to `setEnvironmentVariables.js`, keeping
   the existing per-name exports in place. Nothing consumes `BUILD_ARGS` yet, so
   this is inert and independently revertable.
2. Switch the four call sites to `build-args: ${{ env.BUILD_ARGS }}`, and verify
   the emitted set against the step-1 baseline.
3. Drop the per-name exports that nothing reads any more, keeping `FLUTTER_VERSION`
   and `IMAGE_REPOSITORY_PATH` (D3).

Rollback: each step is a separate commit; step 2 is the only one that changes what
is passed to a build.

## Open Questions

1. **Does `windows.Dockerfile` eventually adopt this?** It would need a different
   emission shape (PowerShell array, not newline pairs). Out of scope here;
   revisit if the Windows leg migrates to `docker/build-push-action`.
