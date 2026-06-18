## 1. Anonymous manifest-resolution script

- [x] 1.1 Add `script/verify_published_image.sh` taking `<registry> <repository>
  <tag>` (e.g. `ghcr.io gmeligio/flutter-android 3.44.1`). `set -euo pipefail`.
- [x] 1.2 Map registry host: `docker.io`/`registry-1.docker.io` →
  `registry-1.docker.io`; `ghcr.io` → `ghcr.io`; `quay.io` → `quay.io`.
- [x] 1.3 Implement the standard token handshake: `HEAD /v2/<repo>/manifests/<tag>`
  with an OCI-index + manifest-list + manifest `Accept` header; on `401`, parse
  `WWW-Authenticate: Bearer realm=…,service=…,scope=…`, fetch a token from the
  realm **with no credentials**, retry with `Authorization: Bearer <token>`.
- [x] 1.4 Exit `0` only on a final `200`; exit non-zero on `401`/`403`/any other
  status, logging `<registry>/<repo>:<tag> → HTTP <code> (<resolvable|NOT
  resolvable>)` and, on failure, a message naming the exact pair.

## 2. `verify-published` job in `release.yml`

- [x] 2.1 Add a `verify-published` job: `runs-on: ubuntu-24.04`,
  `needs: [release-android, release-windows]`, `if: ${{ always() &&
  (needs.release-android.result == 'success' || needs.release-windows.result ==
  'success') }}`. Harden runner + checkout, consistent with sibling jobs.
- [x] 2.2 The job performs **no** `docker/login-action` for any registry.
- [x] 2.3 When `needs.release-android.result == 'success'`, run the script for
  `flutter-android` against `docker.io`, `ghcr.io`, and `quay.io` at
  `${{ github.ref_name }}` (the released version).
- [x] 2.4 When `needs.release-windows.result == 'success'`, run the script for
  `flutter-windows` against the same three registries at `${{ github.ref_name }}`.
- [x] 2.5 Any failing check fails the job (and thus the release run). Confirm no
  `needs:` edge was introduced between `release-android` and `release-windows`.

## 3. One-time ops: GHCR visibility

- [ ] 3.1 In the GitHub UI (org/user package settings), set the
  `flutter-android` GHCR package visibility to **Public** and confirm it is
  linked to the repository. (Cannot be done by the workflow's `GITHUB_TOKEN`.)
- [ ] 3.2 Acknowledge the side effect: `:buildcache` and live `pr-*`/`branch-*`
  tags become publicly pullable. Harmless — public-repo build artifacts;
  `cleanup-pr-image.yml` GCs PR tags.

## 4. Verify (built-in correctness check)

- [x] 4.1 **Before** the GHCR flip, run the script locally against the current
  release `3.44.1`. Confirm it exits non-zero for
  `ghcr.io gmeligio/flutter-android 3.44.1` (reproduces #492) and exits zero for
  `docker.io gmeligio/flutter-android 3.44.1` and
  `ghcr.io gmeligio/flutter-windows 3.44.1`.
- [ ] 4.2 Settle Quay: run the script for `quay.io gmeligio/flutter-android
  3.44.1` and `quay.io gmeligio/flutter-windows 3.44.1`. If non-zero, perform the
  same one-time public-visibility action on Quay and note it in the PR.
- [ ] 4.3 **After** the GHCR flip, re-run 4.1 for GHCR and confirm it now exits
  zero.
- [ ] 4.4 On the next real release run, confirm `verify-published` executes,
  checks the published pairs, and is green. Paste the per-pair log lines into the
  PR.

## 5. Archive

- [ ] 5.1 After merge, sync the `ci-image-anonymous-availability` spec to shipped
  behavior and move this change to
  `openspec/changes/archive/<YYYY-MM-DD>-p14-verify-anonymous-image-availability/`.
