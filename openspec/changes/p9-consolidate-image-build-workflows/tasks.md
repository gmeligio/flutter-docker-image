## 1. Build the reusable image-build workflow

- [ ] 1.1 Create `.github/workflows/build-image.yml` with `on: workflow_call` and inputs: `runner-os`, `dockerfile`, `image-name`, `push-to-registries` (boolean), `cache-mode` (`gha`|`registry`), `tag-prefix`. Declare `secrets:` for Docker Hub and Quay credentials with `required: false`.
- [ ] 1.2 Body: harden-runner → `setup-build-context` → `docker-registry-login` (gated on caller passing secrets) → `docker/metadata-action` → `docker/build-push-action` → `container-structure-test-action` → conditional `docker/scout-action`.
- [ ] 1.3 Emit outputs: `image-digest`, `image-tag`, `metadata-json`. Document each in a header comment.
- [ ] 1.4 Add `permissions:` at workflow level (`contents: read`); per-job escalation only where needed (`packages: write` for the push step).

## 2. Rewrite caller workflows as thin shims

- [ ] 2.1 Rewrite `build.yml` (PR/dispatch trigger) as a caller of `build-image.yml` with `runner-os: ubuntu-24.04`, `push-to-registries: false` for fork PRs (gated by the caller-side `if:`), cache mode `gha`. Preserve the existing handoff-tag computation by moving it to a small script under `script/` if it does not fit cleanly into the reusable inputs.
- [ ] 2.2 Rewrite `ci.yml` (push main) as a caller with `push-to-registries: true`, cache mode `registry`.
- [ ] 2.3 Rewrite `windows.yml` as a caller with `runner-os: windows-2025`.
- [ ] 2.4 Rewrite `release.yml`'s image-build job as a caller with `push-to-registries: true`, full tag set. Preserve `release.yml`'s non-image jobs (release notes, Docker Hub description sync, etc.).

## 3. Merge changelog+tag into prepare-release

- [ ] 3.1 Create `.github/workflows/prepare-release.yml` with `on: push` to `main` for paths `config/version.json`, plus `workflow_dispatch`. Two jobs: `update-changelog` → `create-tag` (with `needs: update-changelog`).
- [ ] 3.2 Job `update-changelog`: lift the steps from current `changelog.yml`.
- [ ] 3.3 Job `create-tag`: lift the steps from current `tag.yml`. The `needs:` dependency replaces the file-push trigger chain.
- [ ] 3.4 Delete `changelog.yml` and `tag.yml`.

## 4. Rename underscore workflows to kebab-case

- [ ] 4.1 `git mv` `update_version.yml` → `update-version.yml`. Update the `name:` key inside the file. Search for any `workflow:` reference in other workflows and update.
- [ ] 4.2 `git mv` `update_docs.yml` → `update-docs.yml`. Update `name:` and references.
- [ ] 4.3 `git mv` `cleanup_pr_image.yml` → `cleanup-pr-image.yml`. Update `name:` and references.
- [ ] 4.4 Do the rename in a single commit separate from the rewrite commits so `git log --follow` works for future archeology.

## 5. Update external references

- [ ] 5.1 Update `README.md` workflow badges to the new filenames.
- [ ] 5.2 Enumerate branch protection required-checks; update any pinned check names (Settings → Branches → Edit rule → Status checks). Do this BEFORE merging or the post-merge run will be blocked.
- [ ] 5.3 Update any links in `openspec/specs/*/spec.md` that reference renamed workflows by filename.

## 6. Verify

- [ ] 6.1 In a draft PR: `workflow_dispatch` each rewritten caller; compare the built image digest against the most recent `main` run for the same input. They should match (Docker build is deterministic for an unchanged context).
- [ ] 6.2 Push a no-op edit to `config/version.json` on a branch and `workflow_dispatch` `prepare-release.yml`; confirm `update-changelog` runs, then `create-tag` runs, then `release.yml` is triggered by the new tag — full chain works.
- [ ] 6.3 Confirm Scorecard scan still passes after merge (no `TokenPermissionsID` regressions introduced by the new `build-image.yml` workflow).
- [ ] 6.4 Confirm renamed-workflow runs appear in the Actions UI; archive any old run histories that point to the deleted filenames.
