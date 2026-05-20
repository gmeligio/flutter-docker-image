## Why

`build.yml/test_image` runs `Test image` (~4½ min, container-structure-test) and `Scan with Docker Scout` (~9 min, vulnerability scan) **back-to-back in the same job** even though neither depends on the other's output. Each consumes the just-built image independently. The serial layout makes Scout the long pole of every PR run, holding the job at ~20 min wall-clock when ~12 min is achievable.

The existing `build.yml:108` TODO explicitly notes this:

> `# TODO: Parallelize testing and vulnerability scanning`

`docker/scout-action` accepts a remote image reference (`registry://` prefix per the action README, no daemon required), and `container-structure-test` runs against any image present in the local Docker daemon (the `plexsystems/container-structure-test-action` does not pull on its own, so consumers on the registry path SHALL `docker pull` before invoking it). With the handoff established by p2, the two consumers can run as sibling jobs that each materialize the handoff image independently.

## What Changes

- **Rename** `test_image` job → `build_image`. Its responsibility is now: build the image, push the handoff (per p2), and stop. Remove the `Test image` and `Scan with Docker Scout` steps from this job.
- **New job** `test_image` (`needs: build_image`): materializes the handoff into the local Docker daemon (registry-path: `docker pull <image_ref>`; artifact-path: `download-artifact` + `docker load`), runs container-structure-test against the loaded image.
- **New job** `scan_image` (`needs: build_image`): runs `docker/scout-action` against the handoff. Registry-path `docker pull`s the GHCR image, re-tags it to the Docker Hub repo path (`<owner>/flutter-android:<flutter_version>`), and passes `image: local://<repo-path>` — Scout's `compare` requires the Docker Hub repo path to look up stream-environment records (`registry://ghcr.io/...` fails with "not in stream environment:prod"). Artifact-path uses `image: local://<image_local_tag>` after `download-artifact` + `docker load`. Gated `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` (Scout needs the Docker Hub org secret + PR-comment write, neither available to fork PRs — matches the existing gate at `build.yml:155`).
- Both consumer jobs run on `ubuntu-24.04` with a thin checkout + login + pull-or-load + the existing validation step. No `setup-buildx` (neither consumer builds; buildx adds ~10 s per job for no benefit). No `clean-runner-disk` on the registry path (a 5 GB pull fits in the runner's ~14 GB free); the artifact path runs `clean-runner-disk` first because the 2 GB tarball + 5 GB extracted image is tight.
- Pin `docker/scout-action` to **v1.20.4** (current as of Apr 2026; today's pin is v1.18.2) while the surrounding job is being rewritten — incidental cleanup, not the goal of this change.
- `build_image` keeps `clean-runner-disk` (the build still needs the headroom).
- Move the `permissions.security-events: write` from `build_image` to `scan_image` (Scout writes SARIF), and `permissions.pull-requests: write` likewise.

```
  BEFORE (one job, serial)              AFTER (three jobs, parallel)

  ┌──────────────────────────┐          ┌──────────────────────┐
  │ test_image  ~20m         │          │ build_image  ~6m     │
  │   clean ........ 3m      │          │   clean ........ 3m  │
  │   build ........ 2½m     │          │   build+push .... 3m │
  │   CST .......... 4½m     │          └──────┬───────────────┘
  │   Scout ........ 9m      │                 │
  └──────────────────────────┘            ┌────┴─────┐
                                          ▼          ▼
                                    ┌──────────┐ ┌──────────────┐
                                    │test_image│ │ scan_image   │
                                    │ pull+CST │ │ Scout(reg://)│
                                    │   ~5m    │ │      ~9m     │
                                    └──────────┘ └──────────────┘

                                    Total wall: 6m + max(5,9) ≈ 15m
                                    (vs. 20m → saves ~5m; with p1 ~7m)
```

## Capabilities

### New Capabilities

- `ci-parallel-image-validation`: defines the contract that container-structure testing and vulnerability scanning of the Flutter Docker image SHALL run as siblings — not as serial steps in the same job — and the dependency rules each consumer SHALL satisfy.

### Modified Capabilities

_None._ p2's `ci-image-handoff` is consumed but not modified.

## Impact

- **Affected files**: `.github/workflows/build.yml` (substantial reorganization of the `test_image` job into three jobs).
- **Behavioral change**: PR check page shows three checks (`build_image`, `test_image`, `scan_image`) instead of one (`test_image`). Required-status-check protection rules on `main` SHALL be updated to require the new names — branch protection is the migration blocker, called out explicitly in tasks.
- **Wall-clock win**: ~5 min saved per PR run on non-fork PRs (post-p1: ~7 min). Fork PRs save the same, paid via ~2 min of artifact upload/download overhead — net ~3 min saved.
- **Risk**: a fork-PR consumer job loading a 2 GB artifact and then `docker load`-ing it adds disk pressure on the consumer runners. Mitigation: consumer jobs run `clean-runner-disk` selectively when `image_artifact` is non-empty (artifact path), skip it when `image_ref` is set (registry path uses streaming pull, no save-file on disk).
- **Depends on**: p2 (handoff). Cannot land without it.
- **Out of scope**: changing what CST or Scout do, splitting CST configs by Dockerfile stage, Windows image parallelization.
