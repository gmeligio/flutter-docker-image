## 1. Add the GHCR push to the build step

- [x] 1.1 Reuse the existing `Login to GHCR` step at `build.yml:75-81` (landed via p1). Confirm its predicate (`github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`) matches the fork-PR gate used in 1.3 — they must agree.
- [x] 1.2 Compute the handoff tag in a shell step: `pr-${{ github.event.pull_request.number }}` for `pull_request`, `branch-${{ github.ref_name }}` (with `/` → `-`) for `workflow_dispatch`. Emit as `steps.handoff.outputs.tag`.
- [x] 1.3 Compute the fork predicate as `steps.handoff.outputs.is_fork`: `github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository`.
- [x] 1.4 Update the `docker/build-push-action` step to emit both a local docker image and a registry push when `is_fork == false`. Replace `load: true` with a multi-line `outputs:` (note: `load` and `push` shorthands are mutually exclusive, so neither can be set when `outputs:` is used):

  ```yaml
  outputs: |
    type=docker,name=${{ steps.metadata.outputs.tags }}
    type=registry,push=true,name=ghcr.io/${{ github.repository_owner }}/flutter-android:${{ steps.handoff.outputs.tag }}
  ```

  Place `type=docker` before `type=registry` (digest-ordering nuance, [discussion #1318](https://github.com/docker/build-push-action/discussions/1318)). For fork PRs (`is_fork == 'true'`), emit only `type=docker` so the existing serial test/scout still has a local image. Satisfies spec scenario "Non-fork PR pushes the handoff tag".

## 2. Add the fork-PR artifact fallback

- [x] 2.1 Add a step gated `if: steps.handoff.outputs.is_fork == 'true'` that runs `docker save <metadata.tags[0]> | gzip > image.tar.gz`.
- [x] 2.2 Add an `actions/upload-artifact@v5` step gated on the same predicate, with `name: image-${{ github.run_id }}`, `path: image.tar.gz`, `retention-days: 1`, `compression-level: 0` (already gzipped).

## 3. Expose job outputs

- [x] 3.1 Add `outputs:` to the `test_image` job:
  - `image_ref: ${{ steps.handoff.outputs.is_fork == 'true' && '' || format('ghcr.io/{0}/flutter-android:{1}', github.repository_owner, steps.handoff.outputs.tag) }}`
  - `image_artifact: ${{ steps.handoff.outputs.is_fork == 'true' && format('image-{0}', github.run_id) || '' }}`
  - `image_local_tag: ${{ format('flutter-android:{0}', env.FLUTTER_VERSION) }}` — always set; the tag both the locally-loaded image and the `docker save` tarball carry.
  - Satisfies spec scenario "Outputs encode the handoff kind unambiguously".

## 4. Verify on a real PR before merge

- [x] 4.1 Push as a non-fork draft PR. Confirm the tag `ghcr.io/<owner>/flutter-android:pr-<N>` appears under GHCR Packages, the job output `image_ref` is populated, and the existing `Test image` and `Scout` steps still pass on the locally-loaded image.
- [x] 4.2 Push from a fork (or simulate by gating the predicate to always-true for one run). Confirm the artifact `image-<run_id>` is uploaded (~2 GB), the output `image_artifact` is populated, and `image_ref` is empty.
- [x] 4.3 Re-run the same PR. Confirm the existing `pr-N` tag is overwritten in place (no duplicate `pr-N-1`, `pr-N-2`, etc.) — satisfies spec scenario "Re-running a PR overwrites the same handoff tag".

## 5. Post-merge closure check

- [x] 5.1 After 5 post-merge PRs, list GHCR tags matching `pr-*` and confirm they accumulate (cleanup is p4, not this change).
- [x] 5.2 Confirm fork-PR build wall-clock has regressed by ≤ 3 minutes vs. pre-change median — this is the expected cost until p3 redeems it.
