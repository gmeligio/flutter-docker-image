## 1. Add the `release_windows` job to `release.yml`

- [ ] 1.1 Open `.github/workflows/release.yml` and add a new job `release_windows` after `release_android`. Set `runs-on: windows-2025`, `permissions.packages: write`, `env.IMAGE_REPOSITORY_NAME: flutter-windows`, `env.VERSION_MANIFEST: config/version.json`.
- [ ] 1.2 Add a `Checkout repository` step using the same SHA-pinned `actions/checkout` already in use elsewhere in the file.
- [ ] 1.3 Add a `Read environment variables from the version manifest` step using `actions/github-script` and `script/setEnvironmentVariables.js`, identical to `release_android`.
- [ ] 1.4 Add a `Load image metadata` step using `docker/metadata-action` with `images:` set to `${{ env.IMAGE_REPOSITORY_PATH }}`, `ghcr.io/${{ env.IMAGE_REPOSITORY_PATH }}`, `quay.io/${{ env.IMAGE_REPOSITORY_PATH }}` and `tags: type=raw,value=${{ env.FLUTTER_VERSION }}`.

## 2. Wire registry logins

- [ ] 2.1 Add `Login to Docker Hub` step using `docker/login-action` with `${{ secrets.DOCKER_HUB_USERNAME }}` / `${{ secrets.DOCKER_HUB_TOKEN }}`.
- [ ] 2.2 Add `Login to GitHub Container Registry` step with `registry: ghcr.io`, `${{ github.actor }}` / `${{ github.token }}`.
- [ ] 2.3 Add `Login to Quay.io` step with `registry: quay.io`, `${{ secrets.QUAY_USERNAME }}` / `${{ secrets.QUAY_ROBOT_TOKEN }}`.

## 3. Build and push the Windows image

- [ ] 3.1 Add a `Build image` step running `docker build . -f windows.Dockerfile --target flutter --build-arg flutter_version=${{ env.FLUTTER_VERSION }}` followed by `docker tag` calls that apply each metadata-action tag to the local image.
- [ ] 3.2 Add the OCI labels emitted by `metadata-action` to the build using `--label` arguments (or pipe the labels via a script step that iterates `${{ steps.metadata.outputs.labels }}`).
- [ ] 3.3 Add a `Push to registries` step that runs `docker push` for each tag in `${{ steps.metadata.outputs.tags }}` (one push per registry-prefixed tag).

## 4. Confirm parallelism and isolation from `release_android`

- [ ] 4.1 Verify the new job has no `needs:` line and no `if:` line keying on `release_android` outcome — it must run in parallel.
- [ ] 4.2 Verify the existing `update_description`, `record_image`, `set_bootstrap_image`, and `create_github_release` jobs still `needs: release_android` only, not `release_windows`.
- [ ] 4.3 Add `if: github.event_name == 'push'` to `release_android` so that `workflow_dispatch` runs `release_windows` in isolation. The four Android-side downstream jobs auto-skip via their existing `needs: release_android` (GitHub Actions skips dependents when their `needs` job is skipped), so no `if:` clause is added to them.

## 5. Confirm gx pinning compliance

- [ ] 5.1 Confirm every `uses:` action in the new job is already entered in `.github/gx.toml` (it should be, since they all appear in `release_android`).
- [ ] 5.2 Add a new entry to `[actions.overrides]."docker/metadata-action"` in `.github/gx.toml` for the new `release_windows` step, pinned at `~5.10.0` for parity with `release_android` (the existing `~5.7.0` entry for `windows.yml::test_windows` is unrelated and is left untouched in this change).
- [ ] 5.3 Run `gx tidy` locally; the diff should be empty after 5.2 lands. If it isn't, commit the gx-managed updates with the change.
- [ ] 5.4 Run `gx lint` locally to confirm SHA pinning is correct.

## 6. Pre-merge dry run

- [ ] 6.1 Push the branch and open a PR. The `pull_request` checks do not exercise `release.yml`, so the PR is evaluated on YAML review only.
- [ ] 6.2 After merge, use `workflow_dispatch` to trigger `release.yml` against the most recent stable Flutter tag. The run SHALL report `release_windows` as success and `release_android`, `update_description`, `record_image`, `set_bootstrap_image`, and `create_github_release` all as `skipped`. A green workflow run is the success criterion.
- [ ] 6.3 Confirm `release_windows` exits 0 and the three published manifests exist:
  - `docker manifest inspect docker.io/<org>/flutter-windows:<version>`
  - `docker manifest inspect ghcr.io/<org>/flutter-windows:<version>`
  - `docker manifest inspect quay.io/<org>/flutter-windows:<version>`
- [ ] 6.4 Confirm `docker.io/<org>/flutter-android:<version>` digest is unchanged from the original tag-time publish. This is structurally guaranteed by the `if:` guard on `release_android` (task 4.3), but verify once on the first dry-run.

## 7. Confirm OCI labels and version match

- [ ] 7.1 Run `docker pull docker.io/<org>/flutter-windows:<version>` and `docker inspect` it.
- [ ] 7.2 Confirm `Labels["org.opencontainers.image.version"]` equals `<version>` and `Labels["org.opencontainers.image.revision"]` equals the tag's commit SHA.
- [ ] 7.3 Run the image and confirm `flutter --version` reports `<version>`.

## 8. Archive

- [ ] 8.1 After merge and successful first real (non-dispatch) release, archive this change so the `windows-image-release` spec is promoted to `openspec/specs/`.
