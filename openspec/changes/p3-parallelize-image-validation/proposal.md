## Why

`build.yml/test_image` runs `Test image` (~4½ min, container-structure-test) and `Scan with Docker Scout` (~9 min, vulnerability scan) **back-to-back in the same job** even though neither depends on the other's output. Each consumes the just-built image independently. The serial layout makes Scout the long pole of every PR run, holding the job at ~20 min wall-clock when ~12 min is achievable.

The existing `build.yml:108` TODO explicitly notes this:

> `# TODO: Parallelize testing and vulnerability scanning`

`docker/scout-action` accepts a remote image reference (`registry://` prefix per the action README), and `container-structure-test` runs against any locally-loadable image. With the handoff established by p2, the two consumers can run as sibling jobs that each pull the handoff image independently.

## What Changes

- **Rename** `test_image` job → `build_image`. Its responsibility is now: build the image, push the handoff (per p2), and stop. Remove the `Test image` and `Scan with Docker Scout` steps from this job.
- **New job** `test_image` (`needs: build_image`): pulls the handoff (registry or artifact, depending on `build_image.outputs.image_ref` / `image_artifact`), runs container-structure-test against it.
- **New job** `scan_image` (`needs: build_image`): pulls the handoff, runs `docker/scout-action` against it. Gated `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` (Scout needs the Docker Hub org secret + PR-comment write, neither available to fork PRs — matches the existing gate at `build.yml:113`).
- Both consumer jobs run on `ubuntu-24.04` with a thin checkout + setup-buildx + login + pull-or-load + the existing validation step. No `clean-runner-disk` needed in the consumer jobs because they do not build (they only pull the ~5 GB image).
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
                                    ┌──────────┐ ┌──────────┐
                                    │test_image│ │scan_image│
                                    │ pull+CST │ │pull+Scout│
                                    │   ~5m    │ │    ~9m   │
                                    └──────────┘ └──────────┘

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
