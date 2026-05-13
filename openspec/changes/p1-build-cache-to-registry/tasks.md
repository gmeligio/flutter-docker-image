## 1. Swap the cache backend in `build.yml`

- [x] 1.1 Add a `Login to GHCR` step to the `test_image` job, after `Login to Docker Hub`, gated `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` (fork PRs cannot push). Use `docker/login-action` with `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`.
- [x] 1.2 Replace `cache-from: type=gha` with `cache-from: type=registry,ref=ghcr.io/${{ github.repository_owner }}/flutter-android:buildcache` in `build.yml:89`.
- [x] 1.3 Replace `cache-to: type=gha,mode=max` with `cache-to: type=registry,ref=ghcr.io/${{ github.repository_owner }}/flutter-android:buildcache,mode=max` in `build.yml:90`. Gate the value: only set it when the fork-PR predicate is true; otherwise omit `cache-to` entirely (use a YAML conditional or templated string). Cleanest implementation is a `cache-to` value of `${{ predicate && 'type=registry,...,mode=max' || '' }}`.
- [x] 1.4 Confirm `permissions.packages: write` is set on the `test_image` job (already present for Scout) — satisfies spec scenario "Non-fork PR populates the registry cache".

## 2. Verify on a real PR before merge

- [ ] 2.1 Push as a draft PR. Confirm the first `build.yml` run pushes the cache to `ghcr.io/.../flutter-android:buildcache` (visible under the Packages tab) and the second run hits it (visible in the `Build image` step log: `importing cache manifest from ghcr.io/...:buildcache`).
- [ ] 2.2 Open a PR from a fork (or simulate via a non-`packages:write` token). Confirm `cache-to` is not attempted and the build still succeeds, falling back to a cold build with the registry as `cache-from` only.
- [ ] 2.3 Record build-step durations from 3 consecutive runs in the PR description: cold (first), warm (second), warm (third). Compare against the pre-change median (~2m23s on cache-hit).

## 3. Post-merge closure check

- [ ] 3.1 After 10 post-merge runs of `build.yml`, query `gh run list --workflow=build.yml --limit 20 --status completed` and confirm the median `Build image` step duration is ≤ 90s. If not, investigate whether the cache is being evicted or the `buildcache` tag is being overwritten by a parallel branch.
- [ ] 3.2 Confirm no growth in the `flutter-android:buildcache` tag size over the first week. `mode=max` rewrites the manifest in place; if size grows monotonically, an issue exists.
