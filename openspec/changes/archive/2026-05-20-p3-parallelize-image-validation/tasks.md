## 1. Rename `test_image` → `build_image` and strip the validation steps

- [x] 1.1 Rename the `test_image` job key in `build.yml` to `build_image`. Update any references in the workflow.
- [x] 1.2 Remove the `Test image` step (`plexsystems/container-structure-test-action`) from `build_image`.
- [x] 1.3 Remove the `Scan with Docker Scout` step from `build_image`.
- [x] 1.4 Keep `clean-runner-disk`, buildx setup, logins, metadata, and the build+push step (per p2).
- [x] 1.5 Drop `permissions.security-events: write` and `permissions.pull-requests: write` from `build_image` — they belong to `scan_image` now.

## 2. Add the new `test_image` consumer job

- [x] 2.1 Add a job `test_image` with `needs: build_image`, `runs-on: ubuntu-24.04`, `permissions.contents: read` and `permissions.packages: read`. Do NOT add `setup-buildx-action` — the job does not build.
- [x] 2.2 Checkout the repo (CST needs `test/android.yml`).
- [x] 2.3 Branch on `needs.build_image.outputs.image_artifact`:
  - Non-empty (fork PR): run `clean-runner-disk`, `download-artifact`, `gunzip`, `docker load`, then invoke CST against `needs.build_image.outputs.image_local_tag`.
  - Empty (non-fork): GHCR login (read) + `docker pull "$IMAGE_REF"` (where `IMAGE_REF=needs.build_image.outputs.image_ref`), then invoke CST against `IMAGE_REF`. The pull is required because `plexsystems/container-structure-test-action` does not pass `--pull` and the underlying CLI's `docker` driver only inspects the local daemon — passing a registry ref without a prior pull fails with "image not found".
- [x] 2.4 Use `plexsystems/container-structure-test-action` with `config: test/android.yml` and `image: <ref-or-loaded-tag>` — satisfies spec scenario "Test job runs in parallel with scan job".

## 3. Add the new `scan_image` consumer job

- [x] 3.1 Add a job `scan_image` with `needs: build_image`, `runs-on: ubuntu-24.04`, `permissions.packages: read`, `permissions.pull-requests: write`, `permissions.security-events: write`. Do NOT add `setup-buildx-action` — the job does not build, and Scout reads from the registry directly.
- [x] 3.2 Gate the entire job: `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` (Scout's existing fork gate).
- [x] 3.3 Branch on `image_artifact`:
  - Non-empty (artifact path): `clean-runner-disk`, `download-artifact`, `gunzip`, `docker load`, then pass `image: local://<image_local_tag>` to `docker/scout-action`.
  - Empty (registry path): GHCR login (read), then pass `image: registry://<image_ref>` to `docker/scout-action` — no `docker pull` needed (the `registry://` prefix tells Scout to bypass the local image store).
- [x] 3.4 Preserve all current Scout inputs: `command: compare, recommendations`, `github-token`, `only-fixed: true`, `organization: ${{ secrets.DOCKER_HUB_USERNAME }}`, `to-env: prod`.
- [x] 3.5 Bump the `docker/scout-action` pin from v1.18.2 → **v1.20.4** (current as of Apr 2026) while rewriting the step. Incidental cleanup; mention it in the PR body so reviewers can read the release notes (https://github.com/docker/scout-action/releases) and grant approval consciously.
- [x] 3.6 Remove the inline TODO `# TODO: Parallelize testing and vulnerability scanning` — this change resolves it. Satisfies spec scenario "Scout scan runs in parallel with CST".

## 4. Branch-protection migration

- [x] 4.1 Verify the new consumer job key is exactly `test_image` (same as today's monolithic job). The existing required-check named `test_image` continues to be produced — satisfies spec scenario "Renamed consumer preserves the existing required-check name".
- [x] 4.2 Inspect current required checks: `gh api repos/gmeligio/flutter-docker-image/branches/main/protection` → 404 "Branch not protected". No required checks are configured on `main` — no migration needed.
- [ ] 4.3 After this PR merges and produces 3 successful runs on `main`, add `build_image`, `test_image`, and `scan_image` as required status checks. Since no protection exists today, this sets up protection from scratch rather than migrating existing rules.

## 5. Verify on a real PR before merge

- [x] 5.1 PR-A (non-fork): confirm `build_image`, `test_image`, `scan_image` all run, the two consumers start within ~10 s of `build_image` completing, and overall wall-clock is ≤ 15 min (target: ~12-13 min once p1 is in).
- [x] 5.2 PR-A (fork): confirm the artifact path works end-to-end: `build_image` uploads `image-<run_id>`, `test_image` and `scan_image` (scan only if scan would run for forks — it does not today) download and `docker load` and validate.
- [x] 5.3 Confirm that if `test_image` fails but `scan_image` passes (or vice versa), the PR shows the partial failure correctly and re-run-failed reruns only the failed job.

## 6. Post-merge closure check

- [x] 6.1 After 10 post-merge runs, query the median wall-clock of the longest job in `build.yml` and confirm it is ≤ 15 min (down from ~20 min). If above target, investigate which step regressed (likely the `docker pull` on consumers — preferable to fix the cache rather than re-merge).
- [x] 6.2 Sweep open PRs after merge: any in-flight PR built on the old job layout will show the old `test_image` check as missing on rebase. Document the rebase recipe in the merge commit message.
