## 1. Pre-flight verification

- [x] 1.1 Confirm via `rg plexsystems` that the action is referenced only in `.github/workflows/ci.yml`, `.github/workflows/build.yml`, `.github/gx.toml`, and `.github/gx.lock`
- [x] 1.2 Confirm latest `container-structure-test` release on `GoogleContainerTools/container-structure-test` and record version (`v1.22.1`) and the Linux x86_64 asset name (`container-structure-test-linux-amd64`)
- [x] 1.3 Spot-check that `script/container_structure_test.sh` and `script/test_android_from_linux.sh` already invoke the binary as `container-structure-test test --image <ref> --config <path>` (matches the inline run-step we'll add to workflows)

## 2. mise.toml

- [x] 2.1 Add `"github:GoogleContainerTools/container-structure-test[exe=container-structure-test-linux-amd64]" = "1.22.1"` under the `[tools]` table in `mise.toml`
- [x] 2.2 Run `mise install` locally; `mise exec -- container-structure-test version` printed `1.22.1`

## 3. Workflow swap

- [x] 3.1 In `.github/workflows/ci.yml`, replaced the `uses: plexsystems/container-structure-test-action@<sha>` step in the `test_image` job with `run: container-structure-test test --image "<existing-image-expression>" --config test/android.yml` (image expression preserved verbatim)
- [x] 3.2 In `.github/workflows/build.yml`'s `test_image` job, added a `Setup mise tools` step (`uses: jdx/mise-action@1648a7812b9aeae629881980618f079932869151 # v4.0.1`) after the image-load/pull steps and before the test step
- [x] 3.3 In the same `build.yml` job, replaced the `uses: plexsystems/container-structure-test-action@<sha>` step with the inline `run:` step (conditional image expression preserved verbatim)
- [x] 3.4 Repo-wide `rg plexsystems` confirmed zero remaining references in workflows

## 4. gx manifest cleanup

- [x] 4.1 Ran `gx tidy`; output reported `− plexsystems/container-structure-test-action` (1 removed); `.github/gx.toml` no longer contains the entry
- [x] 4.2 `.github/gx.lock` no longer contains the `[actions."plexsystems/..."]` or `[resolutions."plexsystems/..."]` blocks (handled by `gx tidy`)
- [x] 4.3 Repo-wide `rg plexsystems` confirmed zero remaining references anywhere outside openspec

## 5. Local verification

- [x] 5.1 Ran the smoke test against `docker.io/gmeligio/flutter-android:3.41.9` using the mise-installed binary: **9/9 passing**, exit 0
- [x] 5.2 Not applicable — the 3.41.9 production image is not affected by PR #472's regression (build-tools 35.0.0 is what AGP at Flutter 3.41.9 requests, so no runtime download)

## 6. Push and CI verification

- [ ] 6.1 Push branch; confirm `ci.yml :: test_image` passes — in particular that the new `run:` step invokes `container-structure-test` successfully and exits 0 *(deferred — needs push)*
- [ ] 6.2 Confirm `build.yml :: test_image` passes with the added `Setup mise tools` step plus the new `run:` step *(deferred — needs push)*
- [ ] 6.3 Confirm `gx.yml :: lint` (or whatever job validates `gx.toml`/`gx.lock`) passes with the manifest no longer containing `plexsystems/container-structure-test-action` *(deferred — needs push)*
- [ ] 6.4 Confirm no other CI job (security scan, lint, tidy) regressed *(deferred — needs push)*
