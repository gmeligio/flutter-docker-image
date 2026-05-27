## 1. Pre-flight verification

- [ ] 1.1 Confirm via `rg plexsystems` that the action is referenced only in `.github/workflows/ci.yml`, `.github/workflows/build.yml`, `.github/gx.toml`, and `.github/gx.lock`
- [ ] 1.2 Confirm latest `container-structure-test` release on `GoogleContainerTools/container-structure-test` and record version (e.g., `1.22.1`) and the Linux x86_64 asset name (`container-structure-test-linux-amd64`)
- [ ] 1.3 Spot-check that `script/container_structure_test.sh` and `script/test_android_from_linux.sh` already invoke the binary as `container-structure-test test --image <ref> --config <path>` (matches the inline run-step we'll add to workflows)

## 2. mise.toml

- [ ] 2.1 Add `"github:GoogleContainerTools/container-structure-test[exe=container-structure-test-linux-amd64]" = "<version-from-1.2>"` under the `[tools]` table in `mise.toml`
- [ ] 2.2 Run `mise install` locally; confirm `mise exec -- container-structure-test version` prints the pinned version

## 3. Workflow swap

- [ ] 3.1 In `.github/workflows/ci.yml`, replace the `uses: plexsystems/container-structure-test-action@<sha>` step in the `test_image` job with `run: container-structure-test test --image "<existing-image-expression>" --config test/android.yml` (preserve the image expression verbatim). The job already has a `Setup mise tools` step earlier — no other setup change needed.
- [ ] 3.2 In `.github/workflows/build.yml`'s `test_image` job, add a `Setup mise tools` step (`uses: jdx/mise-action@<pinned-sha-from-other-jobs>`) after the image-load/pull steps and before the test step
- [ ] 3.3 In the same `build.yml` job, replace the `uses: plexsystems/container-structure-test-action@<sha>` step with `run: container-structure-test test --image "<existing-image-expression>" --config test/android.yml` (preserve the conditional image expression verbatim)
- [ ] 3.4 Repo-wide `rg plexsystems` to confirm zero remaining references in workflows

## 4. gx manifest cleanup

- [ ] 4.1 Run `gx tidy` (or the mise-shimmed equivalent); confirm `.github/gx.toml` no longer contains `"plexsystems/container-structure-test-action"`
- [ ] 4.2 Confirm `.github/gx.lock` no longer contains an `[actions."plexsystems/container-structure-test-action"."~0.3.0"]` block or a corresponding `[resolutions...]` block
- [ ] 4.3 Repo-wide `rg plexsystems` to confirm zero remaining references anywhere

## 5. Local verification

- [ ] 5.1 Run the smoke test against an existing image using the mise-installed binary: `mise exec -- container-structure-test test --image docker.io/gmeligio/flutter-android:3.41.9 --config test/android.yml`; confirm exit 0 with 9/9 passing
- [ ] 5.2 If the local image has the in-flight build-tools regression (PR #472 not yet merged), document the 8/9 result as expected and rerun once #472 lands

## 6. Push and CI verification

- [ ] 6.1 Push branch; confirm `ci.yml :: test_image` passes — in particular that the new `run:` step invokes `container-structure-test` successfully and exits 0
- [ ] 6.2 Confirm `build.yml :: test_image` passes with the added `Setup mise tools` step plus the new `run:` step
- [ ] 6.3 Confirm `gx.yml :: lint` (or whatever job validates `gx.toml`/`gx.lock`) passes with the manifest no longer containing `plexsystems/container-structure-test-action`
- [ ] 6.4 Confirm no other CI job (security scan, lint, tidy) regressed
