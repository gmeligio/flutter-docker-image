## Context

`container-structure-test` is the binary that runs the Android smoke test in `test/android.yml` against a built image. The repository currently invokes it two ways:

```
LOCAL DEV                                           CI
─────────────────────────────────                   ─────────────────────────────────
script/test_android_from_linux.sh ──▶ binary       ci.yml :: test_image
                                       (on $PATH,                ▼
                                        manual)    uses: plexsystems/container-structure-test-action@<SHA>
                                                                 │
                                                                 ▼
                                                   build.yml :: test_image
                                                                 ▼
                                                   uses: plexsystems/container-structure-test-action@<SHA>
```

The Action is a five-line composite that downloads the upstream binary and runs it with `--image $INPUT_IMAGE --config $INPUT_CONFIG`. Version pinning lives in two places: the Action's `@<SHA>` (pinned in `gx.toml`/`gx.lock`) and an implicit "whichever binary the Action's release shipped." Local-dev pinning lives nowhere — the binary must be on the dev's `$PATH` by whatever means they chose.

The `ci-runtime-tool-versioning` spec already encodes the invariant we want: one `mise.toml`, no other mechanism. Adding `container-structure-test` to that umbrella unifies the local-dev and CI paths and removes one Action SHA from the dependency surface.

The `mise.toml` file already pins `cue`, `git-cliff`, `pnpm`, `node`, and `gx`. The `github:` backend syntax (per `feedback_mise_github_backend.md`) supports the upstream release asset directly: `"github:GoogleContainerTools/container-structure-test[exe=container-structure-test-linux-amd64]" = "1.22.1"`.

## Goals / Non-Goals

**Goals:**

- Make `mise.toml` answer the question "what version of container-structure-test does CI run with?" — the same way it already answers that for `cue`, `node`, `pnpm`, `gx`, `git-cliff`.
- Make `script/container_structure_test.sh` (and the existing `script/test_android_from_linux.sh`) usable verbatim by any local-dev with `mise install` run — no need to track down a binary.
- Drop the `plexsystems/container-structure-test-action` entry from `gx.toml`/`gx.lock` and from the workflow `uses:` references.

**Non-Goals:**

- Changing the smoke-test config (`test/android.yml`) or the image under test. The new invocation produces byte-identical test output for the same image + config.
- Replacing the `jdx/mise-action` itself. `mise-action` is the canonical bootstrap and remains pinned via gx.
- Pinning `container-structure-test` on Windows runners. The Windows smoke-test path (`script/test_android_from_windows.sh`) is dev-only and not exercised in any workflow today; this change only touches the Linux invocations.

## Decisions

### Decision 1: Use mise's `github:` backend for `container-structure-test`

```toml
"github:GoogleContainerTools/container-structure-test[exe=container-structure-test-linux-amd64]" = "1.22.1"
```

**Rationale:** matches the repository's established pattern (`feedback_mise_github_backend.md`: prefer `github:` over `ubi:`, since `ubi` is deprecated). The `exe=` selector is required because the upstream release publishes binaries for multiple OS/arch combinations (`-darwin-amd64`, `-darwin-arm64`, `-linux-amd64`, `-linux-arm64`, `-linux-ppc64le`, `-linux-s390x`, `-windows-amd64.exe`). The Linux x86_64 selector pins what CI runs on `ubuntu-24.04`.

**Alternatives considered:**

- **`asdf:FeryET/asdf-container-structure-test`** — mise registry lists this as an option. Rejected: adds an asdf-plugin indirection layer; the upstream release assets are well-named and stable.
- **`aqua:GoogleContainerTools/container-structure-test`** — also listed in the registry. Rejected: aqua's registry could become out-of-date relative to upstream; the `github:` backend reads directly from the release page.
- **`ubi:GoogleContainerTools/container-structure-test`** — explicitly forbidden by saved feedback.

### Decision 2: Add a `Setup mise tools` step to `build.yml`'s `test_image` job

The job currently has no `jdx/mise-action` step. Add it right after the existing `Login to GHCR` / image-load steps, before the test invocation. This matches the pattern already in `ci.yml`'s `test_image` job and in `build.yml`'s `validate_version_files`, `validate_generated_config`, `build_docs`, and `test_gradle` jobs.

**Rationale:** the alternative — installing `container-structure-test` ad-hoc via curl — defeats the entire purpose of this change (would violate the `ci-runtime-tool-versioning` invariant).

### Decision 3: Replace the Action step with an inline `run:` step

```yaml
- name: Test image
  run: container-structure-test test --image "<resolved-image-ref>" --config test/android.yml
```

The image ref expression (`${{ needs.build_image.outputs.image_artifact != '' && needs.build_image.outputs.image_local_tag || ...}}` for `build.yml`; the Docker Hub tag for `ci.yml`) is preserved verbatim.

**Rationale:** mirrors the existing local-dev invocation (`script/container_structure_test.sh`), so the test command itself becomes the same string in both contexts.

### Decision 4: Run `gx tidy` to remove the action entry from `gx.toml`/`gx.lock`

After deleting the `uses: plexsystems/container-structure-test-action@<SHA>` references from both workflows, run `gx tidy` to regenerate the manifest and lock file. This is the same pattern documented in `actions-version-tracking`'s "Adding a new action" scenario, applied in reverse.

**Rationale:** the `actions-version-tracking` spec requires `gx.toml` and `gx.lock` to track every action referenced in workflows. Since we're removing a reference, the manifest must shrink. Doing it by hand-editing `gx.lock` is brittle; `gx tidy` is the supported path.

## Risks / Trade-offs

- **[Behavioral drift between mise-installed binary and Action-vendored binary]** → Both pull from `GoogleContainerTools/container-structure-test` releases. The Action wraps the binary 1:1 (`--image`, `--config` inputs map to the same flags). Mitigation: at apply time, run the smoke test locally via the mise-installed binary against an existing image (e.g., `docker.io/gmeligio/flutter-android:3.41.9`) and confirm 9/9 tests pass — the same result the Action produces today.
- **[Future container-structure-test release renames the Linux x86_64 asset]** → The current name (`container-structure-test-linux-amd64`) has been stable since v1.0. A rename would surface as a Renovate PR with a failing `mise install` step, not a silent CI regression — mise resolves the asset at install time, not at config-load time.
- **[mise installation overhead added to `build.yml`'s test_image job]** → mise installs the tool from a GitHub release; on a cold runner cache this is one extra HTTP fetch (~10MB). Practically: ~1-2 seconds, dwarfed by the Android smoke test's ~3-minute Gradle build. The Action also fetches the binary; net runtime change is negligible.
- **[gx.lock drift if `gx tidy` is not run as part of the change]** → CI's existing `tidy` job (in the `gx.yml` workflow) catches lock-file drift on every PR and fails the check. Mitigation: tasks call out `gx tidy` explicitly; the failing CI check is a backstop.

## Automated Test Strategy

- **Spec-level scenarios** in `specs/ci-runtime-tool-versioning/spec.md` are the durable assertions; each maps to a `grep` or workflow-file invariant a maintainer can re-check.
- **End-to-end test:** the Android smoke test in `test/android.yml` is itself the integration test. Both `ci.yml :: test_image` and `build.yml :: test_image` exercise the new path on every PR. If the mise-installed binary diverges from the Action-vendored one, the smoke test fails the same way it would with the Action — same exit-code surface.
- **Manual verification at apply time:**
  - `mise install` resolves and downloads `container-structure-test` 1.22.1.
  - `mise exec -- container-structure-test version` prints `1.22.1`.
  - `mise exec -- container-structure-test test --image docker.io/gmeligio/flutter-android:3.41.9 --config test/android.yml` exits 0 with 9/9 passing (after the unrelated PR #472 lands, otherwise 8/9 with the known build-tools regression).
  - `gx tidy` produces a clean diff that only removes the `plexsystems` entries from `gx.toml` and `gx.lock`.

## Observability

- **CI failure surfaces in the Actions tab** as today: a smoke-test failure fails the `test_image` job. The error message is now produced by `container-structure-test` directly (not wrapped by the Action) — slightly more verbose, but identical in content.
- **Tool-install failure surfaces in `Setup mise tools` step**, before the test even runs. The CI engineer sees the failing step pointing at mise, not at the smoke test.
- **No silent failure path introduced.** The Action's wrapper-script could theoretically swallow a non-zero exit code (it doesn't, but a future version might); the inline `run:` step propagates exit codes directly.
- **gx lint drift surfaces in the `tidy` job** if `gx.toml`/`gx.lock` aren't regenerated as part of the PR.

## Migration Plan

1. Update `mise.toml` to add `container-structure-test` under `[tools]`.
2. Update `.github/workflows/ci.yml`: replace the `plexsystems/...` step with an inline `run:` step. The job already has `jdx/mise-action`, no other change needed.
3. Update `.github/workflows/build.yml`: add `jdx/mise-action` to the `test_image` job, then replace the `plexsystems/...` step with an inline `run:` step.
4. Run `gx tidy` locally; commit the resulting `gx.toml`/`gx.lock` diff.
5. Push branch; the PR's own `ci.yml :: test_image` and `build.yml :: test_image` jobs are the verification.

**Rollback:** revert the commit. The Action references and `gx.toml`/`gx.lock` entries return; mise.toml's `container-structure-test` entry is harmless if left in place during a partial rollback (it just means the tool is installed but not used by CI).

## Open Questions

(none — all decisions are grounded in either the codebase, the existing `ci-runtime-tool-versioning` spec, or the published upstream `container-structure-test` release artifacts.)
