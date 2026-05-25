## 1. Build the `setup-build-context` composite

- [ ] 1.1 Create `.github/actions/setup-build-context/action.yml` with inputs `fetch-depth` (default `'1'`) and `fetch-tags` (default `'false'`).
- [ ] 1.2 Steps: harden-runner (audit), `actions/checkout` (SHA-pinned), `jdx/mise-action` (SHA-pinned), `actions/github-script` invoking `script/setEnvironmentVariables.js`.
- [ ] 1.3 Forward every env var the script sets via `core.setOutput` so callers can read them from `steps.<id>.outputs.<name>` instead of `env.<name>`. Document in the action's README why outputs are required (env vars set in a composite don't propagate to the caller's job env).

## 2. Build the `docker-registry-login` composite

- [ ] 2.1 Create `.github/actions/docker-registry-login/action.yml` with inputs: `ghcr` (default `'true'`), `dockerhub` (default `'false'`), `quay` (default `'false'`), and the corresponding `*-username` / `*-password` inputs.
- [ ] 2.2 Steps: harden-runner (audit), then conditional `docker/login-action` calls per input (all SHA-pinned).
- [ ] 2.3 In the action's README, document the **caller-side fork-secret gate**: the calling job must wrap the `uses:` in `if: github.event.pull_request.head.repo.full_name == github.repository` whenever it passes Docker Hub / Quay credentials. The composite cannot self-gate because secrets cannot be read by composite actions.

## 3. Migrate call sites

- [ ] 3.1 Replace the checkout+mise+env-script block in: `build.yml`, `ci.yml`, `changelog.yml`, `release.yml` (both occurrences), `tag.yml`, `update_docs.yml`, `windows.yml`, `update_version.yml` (all four occurrences). Adjust callers to read env vars from the composite's outputs.
- [ ] 3.2 Replace the docker-login block in: `build.yml`, `ci.yml`, `release.yml` (both occurrences), `windows.yml`. Preserve the existing fork-secret gate on the calling job.
- [ ] 3.3 Diff each rewritten workflow against the pre-change version; confirm only the setup block changed and that the rest of the workflow is byte-identical.

## 4. Verify on a real PR

- [ ] 4.1 Push as a draft PR; trigger `build.yml`, `ci.yml`, `release.yml` (workflow_dispatch), `windows.yml`, and one `update-version.yml` matrix.
- [ ] 4.2 Compare step-by-step logs against the pre-change runs from `main`; confirm step durations are within ±5 % and that no step is missing or reordered.
- [ ] 4.3 Open a PR from a fork (or simulate one) and confirm the Docker Hub login step in `build.yml` is correctly skipped (the gate moved with the rewrite).
- [ ] 4.4 Confirm Scorecard re-grades cleanly after merge (no new `TokenPermissionsID` regressions).
