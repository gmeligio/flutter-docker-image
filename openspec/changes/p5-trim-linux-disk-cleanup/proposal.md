## Why

`p4-unify-runner-disk-cleanup` (archived) accepted a 3-minute Linux cleanup budget. Step-level timing on recent runs confirms it: `Clean runner disk` consumes ~186 s (3m06s) on `ubuntu-24.04`. Profiling the action reveals that the bulk of this time is spent inside ~15 `apt-get remove` invocations (`.github/actions/clean-runner-disk/action.yml:41-72`), not in the `rm -rf` calls that actually free the most disk.

`apt-get remove` holds the global dpkg lock, runs maintainer scripts, and triggers post-install hooks per package set. For packages whose files we will `rm -rf` immediately afterward (Chrome, Firefox, Azure CLI, Google Cloud SDK, PowerShell, etc.), the apt-managed metadata bookkeeping is wasted work — nothing downstream queries it.

This change replaces the `apt-get remove` calls with direct `rm -rf` of the same paths. Expected wall-clock: ≤ 2 min, saving ~1-2 min per `test_image` and `ci.yml` run.

## What Changes

- In `.github/actions/clean-runner-disk/action.yml` Linux path:
  - **Remove**: all `apt-get remove -y '...'` lines for browsers, .NET, Swift/LLVM, Azure CLI, Google Cloud, PowerShell, mono.
  - **Keep**: `apt-get autoremove -y` + `apt-get clean` once at the end (cleans up dependency cruft from packages already removed and clears `/var/cache/apt`).
  - **Add**: explicit `rm -rf` of the package install dirs that `apt-get remove` previously handled:
    - `/usr/lib/google-cloud-sdk`, `/opt/google-cloud-sdk`, `/usr/bin/gcloud*`
    - `/opt/microsoft/powershell`, `/usr/local/share/powershell`
    - `/opt/microsoft`, `/opt/google` (already present)
    - `/usr/lib/google`, `/usr/bin/google-chrome*`, `/usr/bin/firefox*`
    - `/opt/az`, `/usr/share/az_*`
  - **Keep**: the existing `rm -rf` block for `/usr/lib/jvm`, `/usr/share/dotnet`, `/usr/share/swift`, `/usr/local/.ghcup`, `/usr/local/julia*`, `/usr/local/lib/android`, `/usr/local/share/chromium`, `/opt/microsoft`, `/opt/google`, `/opt/hostedtoolcache`, `/usr/local/bin/minikube`, `/home/runner/.rustup`, `/etc/skel/.rustup`.
- Keep the post-clean disk-free assertion (`≥ 20 GB on /`) — this is the actual safety contract; the spec already requires it.
- Keep the job-summary line.
- No change to the Windows path.
- Update the `ci-runner-disk-cleanup` capability: tighten the Linux budget from `≤ 4 minutes` to `≤ 2 minutes` and relax the "at least the same set of removed paths" wording to "achieves at least the same minimum free space" — the contract is the freed bytes, not the tactic used to free them.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `ci-runner-disk-cleanup`: tighten the Linux time budget and rewrite the "preserve set of removed paths" requirement around the freed-bytes contract that already exists.

## Impact

- **Affected files**: `.github/actions/clean-runner-disk/action.yml` (Linux step only). No workflow YAML changes.
- **Behavioral change**: `clean-runner-disk` Linux wall-clock drops from ~3m06s to ≤ 2m. Saves ~1-2 min on every PR build (`build.yml/test_image` or, after p3 lands, `build.yml/build_image`) and every `ci.yml` push run.
- **Risk**: a package's files might live in a path not covered by the `rm -rf` list, in which case the disk gain regresses. Mitigation: the post-clean assertion (`≥ 20 GB free`) catches this immediately on the first run, before merge.
- **Risk**: a future package install that depends on apt's view of dpkg state could be broken by the removal of `apt-get remove`. Mitigation: the runner image is freshly provisioned each job, and the only `apt-get install` users in the affected workflows are `clean-runner-disk` itself (no others). The `apt-get autoremove` we keep handles dangling deps.
- **Depends on**: `p4-unify-runner-disk-cleanup` archived. Per the user's assumption, this has happened.
- **Out of scope**: Windows cleanup (separate concern), self-hosted runners.
