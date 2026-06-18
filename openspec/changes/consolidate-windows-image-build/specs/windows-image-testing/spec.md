## MODIFIED Requirements

### Requirement: Pull request CI verifies the Windows image on every PR

The `.github/workflows/windows.yml` workflow SHALL run on every `pull_request` event and SHALL verify the Windows image through a caller job that delegates to the reusable `.github/workflows/windows-image.yml` workflow (`uses:`) with `target: test`, `push: false`, `can-login` set to whether the PR head is in this repository, and forwarding only the two Docker Hub secrets (it never pushes, so it does not forward the Quay credentials). The reusable workflow SHALL build `windows.Dockerfile` with `--target test` and run the Pester suite at `test/windows/Windows.Tests.ps1` inside that image. The PR check SHALL fail if the image build fails, if any Pester test fails, or if Pester exits non-zero. `windows.yml` SHALL NOT build `windows.Dockerfile` with its own inline steps.

The experience context is the maintainer reviewing a PR that touches `windows.Dockerfile`, `script/InstallPester.ps1`, `script/RunPester.ps1`, or `test/windows/**` — they get a single red/green check rather than having to build the multi-hour Windows image locally, and that check exercises the exact build definition the release path uses.

#### Scenario: PR check is green when the image is healthy

- **GIVEN** a PR whose `windows.Dockerfile` builds successfully on `windows-2025`
- **AND** every Pester test in `test/windows/Windows.Tests.ps1` passes inside the resulting `test`-target image
- **WHEN** the Windows caller job runs the reusable workflow with `target: test`
- **THEN** the job exits 0
- **AND** the Windows check on the PR is reported as success

#### Scenario: PR check is red when a Pester test fails

- **GIVEN** a PR whose `test`-target image builds successfully
- **AND** at least one Pester test fails (e.g., the Flutter version inside the image does not match `config/version.json`)
- **WHEN** `script/RunPester.ps1` runs
- **THEN** the script exits non-zero (it propagates `$LASTEXITCODE` from `Invoke-Pester`)
- **AND** the Windows caller job is reported as failed on the PR

#### Scenario: PR check is red when the Dockerfile cannot be built

- **GIVEN** a PR that breaks `windows.Dockerfile` (for example, by referencing a `COPY` source path that does not exist)
- **WHEN** the reusable workflow runs `docker build ... --target test`
- **THEN** the build exits non-zero
- **AND** the Windows caller job is reported as failed on the PR

#### Scenario: Fork PR is verified without secrets

- **GIVEN** a pull request opened from a fork (no repository secrets available)
- **WHEN** the Windows caller job runs with `can-login: false`, `push: false`
- **THEN** the image builds `--target test` and the Pester suite runs without any registry login step
- **AND** the PR check reports success or failure based only on the build and Pester result
