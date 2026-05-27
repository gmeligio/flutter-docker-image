## Why

The Android smoke test (`test/android.yml`, run via `container-structure-test`) is invoked from two workflows — `ci.yml:90` and `build.yml:219` — both via the `plexsystems/container-structure-test-action@<SHA>` GitHub Action. That action is a thin wrapper around the upstream `container-structure-test` binary. The repository already runs the same binary directly from local-dev scripts (`script/container_structure_test.sh`, `script/test_android_from_linux.sh`) and the `ci-runtime-tool-versioning` spec already establishes `mise.toml` as the single source of truth for CI runtime tools (currently `cue`, `node`, `pnpm`, `gx`, `git-cliff`). Container-structure-test is conspicuously absent from that enumeration despite being a CI runtime tool, because at the time the spec was written it was vendored through the Action instead of `mise`. The result is a fork in tool-version management: a maintainer asking *"what version of container-structure-test does CI run with?"* has to read the SHA in two workflows, cross-reference the corresponding Action release on GitHub, and trust that the Action's pinned binary matches the local-dev binary that mise installs. Bringing this tool under the same `mise.toml` umbrella collapses the fork, removes one third-party Action dependency from `gx.toml`/`gx.lock`, and makes local dev byte-identical to CI.

## What Changes

- **MODIFIED (workflows):** Replace `plexsystems/container-structure-test-action@<SHA>` with an explicit `mise`-installed binary invocation in both `.github/workflows/ci.yml` (the `test_image` job, which already has a `Setup mise tools` step) and `.github/workflows/build.yml` (the `test_image` job, which will need a `Setup mise tools` step added). The test command becomes `container-structure-test test --image <image> --config test/android.yml`, matching the invocation already used by `script/container_structure_test.sh` and `script/test_android_from_linux.sh`.
- **MODIFIED (`mise.toml`):** Add `container-structure-test` to the `[tools]` table, pinned via mise's `github:` backend against `GoogleContainerTools/container-structure-test` with the `exe=container-structure-test-linux-amd64` selector. Initial version: `1.22.1` (current latest at apply time).
- **MODIFIED (`.github/gx.toml`, `.github/gx.lock`):** Remove the `plexsystems/container-structure-test-action` entry. `gx tidy` will rewrite both files; no manual hand-editing of `gx.lock`.
- **MODIFIED (spec):** Extend `ci-runtime-tool-versioning`'s single-source enumeration to include `container-structure-test`. The existing invariant — "no workflow may install these tools by any other mechanism" — now covers it. The forbidden mechanisms list grows by one entry: the `plexsystems/container-structure-test-action`.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ci-runtime-tool-versioning`: extend the enumerated tool set to include `container-structure-test`, with a forbidden-mechanism scenario covering `plexsystems/container-structure-test-action`. The existing scenarios for `cue`, `node`, `pnpm`, `gx`, `git-cliff` are preserved unchanged.

## Impact

- Affected files: `.github/workflows/ci.yml`, `.github/workflows/build.yml`, `mise.toml`, `.github/gx.toml`, `.github/gx.lock`. No image-build, Dockerfile, or test-config (`test/android.yml`) changes.
- Risk: the mise-installed binary differs in some behavior from the Action's vendored binary (e.g., flag handling, exit-code shape). Mitigation: the Action is itself a 5-line wrapper around `container-structure-test test --image $image --config $config`; the binary is the same artifact published by `GoogleContainerTools/container-structure-test`. Verify at apply time by running the smoke test locally via the mise-installed binary against the same image the Action would have tested, and by watching the first post-merge `build.yml` run.
- Risk: a future `container-structure-test` release ships a binary asset under a different name on the GitHub release, breaking the `exe=container-structure-test-linux-amd64` selector. Mitigation: Renovate already manages `mise.toml` tool versions per `feedback_mise_github_backend.md`; an asset-name change surfaces as a Renovate PR failure to install, not a silent CI regression.
- Risk: dropping the `plexsystems` entry from `gx.toml`/`gx.lock` causes a `gx` lint failure if `gx tidy` was not run. Mitigation: tasks explicitly call out `gx tidy` after the workflow edits; CI's existing `tidy` job catches drift.
- Relevance gate: this change passes — it modifies a spec-level invariant (`ci-runtime-tool-versioning`'s "no workflow may install these tools by any other mechanism" forbidden-mechanism list grows by one). A CI engineer reading the spec needs to know that the container-structure-test version is now answered by `mise.toml`, not by an Action SHA.
