## 1. Create the reusable workflow `.github/workflows/windows-image.yml`

- [x] 1.1 Add `on: workflow_call` with inputs `target` (string, required) and `push` (boolean, required), plus an explicit `secrets:` block naming `DOCKER_HUB_USERNAME`, `DOCKER_HUB_TOKEN`, `QUAY_USERNAME`, `QUAY_ROBOT_TOKEN`, each `required: false` (least privilege — do not use `secrets: inherit`). Reference them as `${{ secrets.<NAME> }}` in the login steps. No `can-login` input.
- [x] 1.2 Add a top-level `permissions: { contents: read }` block (per `ci-workflow-hardening`). Do not add a `concurrency:` block (callers own concurrency; this workflow is `workflow_call`-only).
- [x] 1.3 Define one job on `runs-on: windows-2025` with `env: { IMAGE_REPOSITORY_NAME: flutter-windows, VERSION_MANIFEST: config/version.json }`. Declare `permissions: { contents: read, packages: write }` on the job so a pushing caller can reach GHCR (effective token is the intersection with the caller's grant).
- [x] 1.4 First step: `step-security/harden-runner` (SHA-pinned, `# vX.Y.Z`) with `egress-policy: audit`.
- [x] 1.5 Then: `actions/checkout` (SHA-pinned) → `uses: ./.github/actions/clean-runner-disk` → the "Ensure Docker daemon is running" PowerShell guard (port the exact block from `windows.yml`).
- [x] 1.6 Read the manifest: `actions/github-script` running `script/setEnvironmentVariables.js` (port from `windows.yml`/`release.yml`), exporting `FLUTTER_VERSION`, `GIT_VERSION`, `VS_CMAKE_VERSION`, `VS_WIN11SDK_BUILD`, `VS_VCTOOLS_VERSION`, `IMAGE_REPOSITORY_PATH`.
- [x] 1.7 `docker/metadata-action` (SHA-pinned) with `images:` listing all three registry namespaces (`${{ env.IMAGE_REPOSITORY_PATH }}`, `ghcr.io/...`, `quay.io/...`) and `tags: type=raw,value=${{ env.FLUTTER_VERSION }}` — identical to the Android job.
- [x] 1.8 Logins, all gated `if: ${{ inputs.push }}`: Docker Hub (`secrets.DOCKER_HUB_*`), GHCR (`github.token`), Quay (`secrets.QUAY_*`). All `docker/login-action`, SHA-pinned. No login runs when `push` is false.
- [x] 1.9 Build step (PowerShell): port the `docker build` from `release.yml`, parameterized — pass all five `--build-arg`s, `--target ${{ inputs.target }}`, `--file windows.Dockerfile`, the metadata `--tag`/`--label` args, and `.`. Check `$LASTEXITCODE`.
- [x] 1.10 Post-build tail: when `inputs.push` is true, `foreach ($tag in $tags) { docker push $tag; check $LASTEXITCODE }`; when false, `docker run --rm <first metadata tag>` to execute the Pester suite — no `--env`/`-v`/args (the `test` image bakes in `config/version.json` + test files and overrides ENTRYPOINT/CMD to `RunPester.ps1`). Ensure the `docker run` exit code propagates (it's the last statement, or `if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }`) so a failing Pester test reddens the job.

## 2. Convert `windows.yml` to a caller

- [x] 2.1 Keep `on: { pull_request:, workflow_dispatch: }`, the top-level `permissions: { contents: read }`, and the existing `concurrency:` block (`cancel-in-progress: true`).
- [x] 2.2 Replace the entire `test-windows` job body with `uses: ./.github/workflows/windows-image.yml` and `with: { target: test, push: false }`. Forward no secrets (the test path performs no registry login).
- [x] 2.3 Remove the now-inlined steps (clean-runner-disk, daemon guard, manifest read, metadata, Docker Hub login, build, run) from `windows.yml`.

## 3. Convert `release-windows` to a caller

- [x] 3.1 In `release.yml`, replace the `release-windows` job body with `uses: ./.github/workflows/windows-image.yml`, `with: { target: flutter, push: true }`, and a `secrets:` mapping forwarding all four `DOCKER_HUB_USERNAME`, `DOCKER_HUB_TOKEN`, `QUAY_USERNAME`, `QUAY_ROBOT_TOKEN`.
- [x] 3.2 Keep `permissions: { contents: read, packages: write }` on the `release-windows` caller job (comment: GHCR push); confirm it does **not** declare `needs: release-android` (preserves Android/Windows parallelism).
- [x] 3.3 Remove the now-inlined steps (manifest read, metadata, three logins, build/push) from the `release-windows` job in `release.yml`.

## 4. Validate locally

- [ ] 4.1 YAML-parse `windows-image.yml`, `windows.yml`, and `release.yml`; confirm every `inputs.*` reference resolves to a declared input and every `uses:` target exists.
- [ ] 4.2 Run the repo workflow policy gate (`gx lint`) and resolve findings: SHA-pinning + `# vX.Y.Z` comments on every third-party action (matching the SHAs already used elsewhere in the repo), top-level `permissions:` on the new file, harden-runner first.
- [ ] 4.3 Confirm by inspection that with `push: false` no login step executes (all three logins gate on `push`), and that the test tail's `docker run` exit code propagates to the job.
- [ ] 4.4 Grep that no inline `docker build ... windows.Dockerfile` remains in `windows.yml` or `release.yml`.
- [ ] 4.5 Confirm least privilege: `windows-image.yml` declares an explicit `secrets:` block (no `secrets: inherit`) naming only the four Docker Hub/Quay secrets; the PR caller forwards no secrets; the release caller forwards all four.

## 5. Verify on CI

- [ ] 5.1 Open the PR; confirm the consolidated `test-windows` caller runs `clean-runner-disk`, builds `--target test`, and the Pester suite passes (green Windows check). This exercises the same build the release path will use, minus push.
- [ ] 5.2 Confirm harden-runner appears in the run's Security insights for the Windows build job.
- [ ] 5.3 **Deferred — release runtime gate (verified on the first tag push / `workflow_dispatch` after merge).** `release-windows` builds past Step 21/36 (VS Build Tools) without `not enough space on the disk`, pushes `flutter-windows:<tag>` to Docker Hub, GHCR, and Quay, and `release-android` runs in parallel unaffected.
