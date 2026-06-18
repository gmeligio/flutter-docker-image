## 1. Create the reusable workflow `.github/workflows/windows-image.yml`

- [ ] 1.1 Add `on: workflow_call` with inputs `target` (string, required), `push` (boolean, required), and `can-login` (boolean, required), plus an explicit `secrets:` block naming `DOCKER_HUB_USERNAME`, `DOCKER_HUB_TOKEN`, `QUAY_USERNAME`, `QUAY_ROBOT_TOKEN`, each `required: false` (least privilege — do not use `secrets: inherit`). Reference them as `${{ secrets.<NAME> }}` in the login steps.
- [ ] 1.2 Add a top-level `permissions: { contents: read }` block (per `ci-workflow-hardening`). Do not add a `concurrency:` block (callers own concurrency; this workflow is `workflow_call`-only).
- [ ] 1.3 Define one job on `runs-on: windows-2025` with `env: { IMAGE_REPOSITORY_NAME: flutter-windows, VERSION_MANIFEST: config/version.json }`. Declare `permissions: { contents: read, packages: write }` on the job so a pushing caller can reach GHCR (effective token is the intersection with the caller's grant).
- [ ] 1.4 First step: `step-security/harden-runner` (SHA-pinned, `# vX.Y.Z`) with `egress-policy: audit`.
- [ ] 1.5 Then: `actions/checkout` (SHA-pinned) → `uses: ./.github/actions/clean-runner-disk` → the "Ensure Docker daemon is running" PowerShell guard (port the exact block from `windows.yml`).
- [ ] 1.6 Read the manifest: `actions/github-script` running `script/setEnvironmentVariables.js` (port from `windows.yml`/`release.yml`), exporting `FLUTTER_VERSION`, `GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, `VS_VCTOOLS_VERSION`, `IMAGE_REPOSITORY_PATH`.
- [ ] 1.7 `docker/metadata-action` (SHA-pinned) with `images:` listing all three registry namespaces (`${{ env.IMAGE_REPOSITORY_PATH }}`, `ghcr.io/...`, `quay.io/...`) and `tags: type=raw,value=${{ env.FLUTTER_VERSION }}` — identical to the Android job.
- [ ] 1.8 Logins, gated: Docker Hub `if: ${{ inputs.can-login }}`; GHCR `if: ${{ inputs.push }}` (using `github.token`); Quay `if: ${{ inputs.push }}`. All `docker/login-action`, SHA-pinned.
- [ ] 1.9 Build step (PowerShell): port the `docker build` from `release.yml`, parameterized — pass all five `--build-arg`s, `--target ${{ inputs.target }}`, `--file windows.Dockerfile`, the metadata `--tag`/`--label` args, and `.`. Check `$LASTEXITCODE`.
- [ ] 1.10 Post-build tail: when `inputs.push` is true, `foreach ($tag in $tags) { docker push $tag; check $LASTEXITCODE }`; when false, `docker run --rm <first tag>` to execute the Pester suite (the `test` target's entrypoint).

## 2. Convert `windows.yml` to a caller

- [ ] 2.1 Keep `on: { pull_request:, workflow_dispatch: }`, the top-level `permissions: { contents: read }`, and the existing `concurrency:` block (`cancel-in-progress: true`).
- [ ] 2.2 Replace the entire `test-windows` job body with `uses: ./.github/workflows/windows-image.yml`, `with: { target: test, push: false, can-login: ${{ github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository }} }`, and a `secrets:` mapping forwarding only `DOCKER_HUB_USERNAME` and `DOCKER_HUB_TOKEN` (no Quay — this path never pushes).
- [ ] 2.3 Remove the now-inlined steps (clean-runner-disk, daemon guard, manifest read, metadata, Docker Hub login, build, run) from `windows.yml`.

## 3. Convert `release-windows` to a caller

- [ ] 3.1 In `release.yml`, replace the `release-windows` job body with `uses: ./.github/workflows/windows-image.yml`, `with: { target: flutter, push: true, can-login: true }`, and a `secrets:` mapping forwarding all four `DOCKER_HUB_USERNAME`, `DOCKER_HUB_TOKEN`, `QUAY_USERNAME`, `QUAY_ROBOT_TOKEN`.
- [ ] 3.2 Keep `permissions: { contents: read, packages: write }` on the `release-windows` caller job (comment: GHCR push); confirm it does **not** declare `needs: release-android` (preserves Android/Windows parallelism).
- [ ] 3.3 Remove the now-inlined steps (manifest read, metadata, three logins, build/push) from the `release-windows` job in `release.yml`.

## 4. Validate locally

- [ ] 4.1 YAML-parse `windows-image.yml`, `windows.yml`, and `release.yml`; confirm every `inputs.*` reference resolves to a declared input and every `uses:` target exists.
- [ ] 4.2 Run the repo workflow policy gate (`gx lint`) and resolve findings: SHA-pinning + `# vX.Y.Z` comments on every third-party action (matching the SHAs already used elsewhere in the repo), top-level `permissions:` on the new file, harden-runner first.
- [ ] 4.3 Confirm by inspection that with `can-login: false, push: false` no login step executes, and that GHCR/Quay logins are gated on `push`.
- [ ] 4.4 Grep that no inline `docker build ... windows.Dockerfile` remains in `windows.yml` or `release.yml`.
- [ ] 4.5 Confirm least privilege: `windows-image.yml` declares an explicit `secrets:` block (no `secrets: inherit`) naming only the four Docker Hub/Quay secrets; the PR caller forwards only the two Docker Hub secrets; the release caller forwards all four.

## 5. Verify on CI

- [ ] 5.1 Open the PR; confirm the consolidated `test-windows` caller runs `clean-runner-disk`, builds `--target test`, and the Pester suite passes (green Windows check). This exercises the same build the release path will use, minus push.
- [ ] 5.2 Confirm harden-runner appears in the run's Security insights for the Windows build job.
- [ ] 5.3 **Deferred — release runtime gate (verified on the first tag push / `workflow_dispatch` after merge).** `release-windows` builds past Step 21/36 (VS Build Tools) without `not enough space on the disk`, pushes `flutter-windows:<tag>` to Docker Hub, GHCR, and Quay, and `release-android` runs in parallel unaffected.
