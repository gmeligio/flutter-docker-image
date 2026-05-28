## 1. Build with SBOM + provenance attestations (GHCR-only)

- [x] 1.1 In `.github/workflows/build.yml`, the `Load image metadata` step emits a single GHCR ref under the handoff tag. `images:` is `ghcr.io/<owner>/flutter-android`; `tags:` is `type=raw,value=${{ steps.handoff.outputs.tag }}`. No Docker Hub namespace.
- [x] 1.2 The `Build image` step is split into two `if:`-gated steps:
  - **Step A** — `Build image (push to GHCR with attestations)`, `if: steps.handoff.outputs.is_fork != 'true'`. `push: true`, `sbom: true`, `provenance: mode=max`, no `outputs:`. `id: build` so `steps.build.outputs.digest` is addressable.
  - **Step B** — `Build image (local artifact only)`, `if: steps.handoff.outputs.is_fork == 'true'`. `outputs: type=docker`, no push, no attestations.
- [x] 1.3 Deleted the standalone `Push image to GHCR` step.
- [x] 1.4 `Re-tag image for local handoff` is `if:`-gated to forks only.
- [x] 1.5 `build_image.outputs.image_digest` added — `${{ steps.handoff.outputs.is_fork != 'true' && steps.build.outputs.digest || '' }}`.

## 2. Point Scout at the GHCR digest, compare to latest release tag

- [x] 2.1 In the `Scan with Docker Scout` step, `image:` is `registry://ghcr.io/${{ github.repository_owner }}/flutter-android@${{ needs.build_image.outputs.image_digest }}`.
- [x] 2.2 In the same step, `to:` is `ghcr.io/${{ github.repository_owner }}/flutter-android:${{ needs.setup.outputs.flutter_version }}` (the latest released GHCR tag, sourced from the existing `setup` job).
- [x] 2.3 Drop `to-env: prod` and `organization:` from the step. Drop `recommendations` from `command:`. Keep `only-fixed: true`. No filter flags added (`only-severities`, `ignore-*`).
- [x] 2.4 `scan_image.needs` is `[setup, build_image]` (was `build_image` only).
- [x] 2.5 Keep `Login to Docker Hub` in `scan_image` — required for Scout's DSOS entitlement check (not for image transport; verified empirically on run 26600820178: removing it produces `could not authenticate: user <actor> not entitled to use Docker Scout`). Add a `Login to GHCR` step using `secrets.GITHUB_TOKEN` for pulling source and target images. Add `packages: read` to `scan_image.permissions`.
- [x] 2.6 Delete the now-unused `Pull image and re-tag for Scout` step and the fork artifact-load steps (unreachable under the job-level fork gate).

## 3. Verify on a PR

- [ ] 3.1 Open the implementation PR. Confirm `build_image` succeeds. Confirm `image_digest` job output is a non-empty `sha256:…` value.
- [ ] 3.2 Run `docker buildx imagetools inspect ghcr.io/<owner>/flutter-android:pr-<N>` (locally or as an ad-hoc step). Confirm the output lists both `sbom` and `provenance` attestation manifests attached to the image index.
- [ ] 3.3 Confirm `test_image` still passes. It pulls from GHCR on non-fork; the artifact path is unchanged on fork.
- [ ] 3.4 Confirm `scan_image` runs and the `Scan with Docker Scout` step log indicates Scout consumed the attached SBOM attestation. Record the new step duration.
- [ ] 3.5 Confirm Scout's PR comment shows the `compare` output against the latest release tag (delta vs `flutter_version` from `setup`).
- [ ] 3.6 Compare new step duration to baseline (~9m31s on run 25877980895). Paste before/after numbers into the PR description along with the `imagetools inspect` output from 3.2.

## 4. Document and archive

- [ ] 4.1 After merge, archive this change under `openspec/changes/archive/<YYYY-MM-DD>-p13-scout-sbom-provenance/` per the experimental workflow.
- [ ] 4.2 Open follow-up change directories for the two Future Work items in `proposal.md` §Future Work, in priority order: move-off-gating-path → conditional-paths-filter.
- [ ] 4.3 Optional out-of-band cleanup: retire the orphaned `prod` env stream in the Docker Scout dashboard (no longer referenced by any workflow).
