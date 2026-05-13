## 1. Add the GHCR push to the build step

- [ ] 1.1 Add a `Login to GHCR` step if p1 has not landed. Otherwise reuse the existing one.
- [ ] 1.2 Compute the handoff tag in a shell step: `pr-${{ github.event.pull_request.number }}` for `pull_request`, `branch-${{ github.ref_name }}` (with `/` → `-`) for `workflow_dispatch`. Emit as `steps.handoff.outputs.tag`.
- [ ] 1.3 Compute the fork predicate as `steps.handoff.outputs.is_fork`: `github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository`.
- [ ] 1.4 Update the `docker/build-push-action` step to also push the image when `is_fork == false`. Try `outputs: type=image,push=true,name=ghcr.io/<owner>/flutter-android:<tag>` alongside `load: true`. If multi-output is unreliable, fall back to a second `Push image` step that uses `docker push ghcr.io/<owner>/flutter-android:<tag>` after tagging the loaded image — satisfies spec scenario "Non-fork PR pushes the handoff tag".

## 2. Add the fork-PR artifact fallback

- [ ] 2.1 Add a step gated `if: steps.handoff.outputs.is_fork == 'true'` that runs `docker save <metadata.tags[0]> | gzip > image.tar.gz`.
- [ ] 2.2 Add an `actions/upload-artifact@v5` step gated on the same predicate, with `name: image-${{ github.run_id }}`, `path: image.tar.gz`, `retention-days: 1`, `compression-level: 0` (already gzipped).

## 3. Expose job outputs

- [ ] 3.1 Add `outputs:` to the `test_image` job:
  - `image_ref: ${{ steps.handoff.outputs.is_fork == 'true' && '' || format('ghcr.io/{0}/flutter-android:{1}', github.repository_owner, steps.handoff.outputs.tag) }}`
  - `image_artifact: ${{ steps.handoff.outputs.is_fork == 'true' && format('image-{0}', github.run_id) || '' }}`
  - Satisfies spec scenario "Outputs encode the handoff kind unambiguously".

## 4. Verify on a real PR before merge

- [ ] 4.1 Push as a non-fork draft PR. Confirm the tag `ghcr.io/<owner>/flutter-android:pr-<N>` appears under GHCR Packages, the job output `image_ref` is populated, and the existing `Test image` and `Scout` steps still pass on the locally-loaded image.
- [ ] 4.2 Push from a fork (or simulate by gating the predicate to always-true for one run). Confirm the artifact `image-<run_id>` is uploaded (~2 GB), the output `image_artifact` is populated, and `image_ref` is empty.
- [ ] 4.3 Re-run the same PR. Confirm the existing `pr-N` tag is overwritten in place (no duplicate `pr-N-1`, `pr-N-2`, etc.) — satisfies spec scenario "Re-running a PR overwrites the same handoff tag".

## 5. Post-merge closure check

- [ ] 5.1 After 5 post-merge PRs, list GHCR tags matching `pr-*` and confirm they accumulate (cleanup is p4, not this change).
- [ ] 5.2 Confirm fork-PR build wall-clock has regressed by ≤ 3 minutes vs. pre-change median — this is the expected cost until p3 redeems it.
