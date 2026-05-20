## Context

p2 establishes that the build job produces either a registry tag (`image_ref`) or an artifact (`image_artifact`). This change splits the existing serial `test_image` job into three jobs: `build_image`, `test_image`, `scan_image`. The latter two consume the handoff in parallel.

The non-trivial questions are: (a) how do consumer jobs get the bits onto their runner with minimum overhead, (b) what's the failure model when one consumer fails, and (c) how do we manage branch-protection migration without locking out merges during the transition.

## Goals / Non-Goals

**Goals:**

- `test_image` and `scan_image` run as siblings, not in series.
- The consumer jobs are thin: no `clean-runner-disk` needed unless the artifact path is in use (the pull does not write the full image to disk twice).
- Branch-protection migration is documented and ordered so `main` is never unprotected and a stale required check name doesn't block merges indefinitely.

**Non-Goals:**

- Matrix-ing CST configs (the project has one `test/android.yml`; if it ever grows, that's a separate change).
- Caching the Scout vulnerability DB (no public knob for this per the action README).
- Self-hosted consumers.

## Decisions

### D1. Consumer jobs reach the image with the cheapest call each tool supports

**Decision**: The two consumers use different strategies because the two actions support different things:

- `docker/scout-action`: SHALL `docker pull` the GHCR image, re-tag it as `<owner>/flutter-android:<flutter_version>` (the Docker Hub repo path), and pass `image: local://<owner>/flutter-android:<flutter_version>`. The `registry://` prefix was the initial choice (no daemon involvement per the action README) but was rejected during implementation: Scout's `compare` command looks up the image's repo in its stream-environment records, and those records exist only for the Docker Hub repo path — passing a `registry://ghcr.io/...` ref fails with "not in stream environment:prod". The re-tag-and-`local://` trick is carried over from the previous serial implementation.
- `container-structure-test` (via `plexsystems/container-structure-test-action`): the action invokes `container-structure-test test --image <input>` with no `--pull` flag and no driver override. The CLI's default `docker` driver inspects the local Docker daemon only. So `test_image` SHALL run an explicit `docker pull "$IMAGE_REF"` on the registry path before invoking the action. The earlier draft of this design assumed CST would stream-pull on demand; it does not.

**Alternatives considered**:

- *Replace the plexsystems action with raw `container-structure-test test --pull --image <ref>`.* One step instead of two, and drops a stale dependency (plexsystems' last release was Mar 2023; last commit Aug 2023). Rejected for now: requires a new install step (curl + chmod-and-pin), and the win is ~30 s. Worth revisiting if the action ever blocks an upgrade.
- *Swap to CST's `--driver tar` (no daemon at all, e.g. `crane export <ref> | container-structure-test --driver tar -`).* Smallest disk footprint, but the tar driver has historical limitations around `commandTests` that rely on real process execution. Out of scope for p3.
- *`docker save`-style artifact even for non-fork PRs.* Rejected — wastes the registry-cache work from p1.

**Rationale**: Match the cheapest path to each action's actual behavior, verified against current upstream sources rather than assumed.

### D2. Fork-PR consumers `download-artifact` + `docker load`, gated on `image_artifact != ''`

**Decision**: Both consumer jobs check `needs.build_image.outputs.image_artifact`. When non-empty, run a setup block: `download-artifact` → `gunzip image.tar.gz` → `docker load`. Then use the loaded image's tag (read from `metadata-action` output passed through `build_image.outputs.image_local_tag`) for the CST/Scout call.

**Alternatives considered**:

- *Skip Scout entirely for fork PRs.* Already the status quo (`build.yml:113`). Keep it for the scan job; the test job has no such restriction.
- *Pull from a public mirror.* No public mirror exists for a not-yet-merged fork PR's image.

**Rationale**: The ~2 min artifact handoff cost is paid only on fork PRs and is bounded.

### D3. Branch protection migration

**Decision**: The new consumer job is named `test_image` — the same key as today's monolithic job. The check name `test_image` therefore continues to appear and continues to be required by branch-protection. The new `build_image` and `scan_image` checks are added but are NOT yet required. A follow-up admin action adds them to required status checks once the new layout has shown a few green runs.

**Failure semantics** during the transition:

- If `build_image` fails, `test_image` is skipped. GitHub treats a skipped required check as not-reported → PR cannot merge. Equivalent safety to today.
- If `scan_image` fails but `test_image` passes, the PR can merge. This is a regression in safety relative to today (Scout currently blocks). The gap is bounded to the window between merging this change and the admin adding `scan_image` to required checks. Acceptable transient.

**Alternatives considered**:

- *Aggregator job that `needs: [build_image, scan_image]` and exits 0 under a name like `image-checks`.* Equivalent end-state, more YAML. Rejected because the name-preservation strategy already keeps `main` protected without an extra job.
- *Block this PR until protection is updated in the same merge window.* Rejected — couples a workflow-change PR to admin availability.

**Rationale**: Preserving the existing check name by renaming the consumer is the smallest possible migration. The bounded scan-gap is the price; it is documented so the admin treats it as a follow-up rather than discovering it via an exploit.

## Risks / Trade-offs

- **R1**: A consumer-job pull failure (transient GHCR error) fails one check while the other passes. Re-run-failed re-runs that single job, but the re-run consumes the same `pr-N` tag, which is safe.
- **R2**: If p2 ever pushes an inconsistent `pr-N` (build succeeded but push partially failed), both consumers will fail in the same way. p2's task list requires the push to be a hard failure of the build job, which prevents this.
- **R3**: Fork-PR `docker load` materializes 5 GB on the consumer runner. Run `clean-runner-disk` first on the fork path.
