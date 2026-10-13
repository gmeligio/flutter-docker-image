## Why

Every Linux job in this repo pins `runs-on: ubuntu-24.04`. GitHub made the `ubuntu-26.04` runner image generally available on 2026-09-17 and will move `ubuntu-latest` to it around Oct–Nov 2026 ([changelog](https://github.blog/changelog/2026-09-17-ubuntu-26-generally-available-and-latest-migration/), [actions/runner-images#14747](https://github.com/actions/runner-images/issues/14747)). Moving now keeps CI on the newest supported LTS image and leaves plenty of time before 24.04 is retired.

The `ci-runner-disk-cleanup` spec names `ubuntu-24.04` as the supported Linux runner, and its free-space contract (≥ 20 GB on `/`) depends on the action removing the right paths. The 26.04 image installs LLVM 20, 21 and 22 instead of 16, 17 and 18 ([Ubuntu2604-Readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md)), so the cleanup action would leave several GB on disk. That would put the free-space assertion at risk, and when it fails a maintainer sees an image build fail. That is why this change needs a spec delta.

## What Changes

- In every workflow under `.github/workflows/`, change `runs-on: ubuntu-24.04` to `runs-on: ubuntu-26.04` (30 jobs). `windows-image.yml` stays on `windows-2025`.
- In `.github/actions/clean-runner-disk/action.yml` (Linux path):
  - Replace `/usr/lib/llvm-16 /usr/lib/llvm-17 /usr/lib/llvm-18` with the glob `/usr/lib/llvm-*`, so the step keeps working whatever LLVM versions the image ships.
  - Update the MongoDB comment to say `ubuntu-26.04`.
  - Leave the `rm -rf` lines for Swift, Julia and Mono in place. The 26.04 readme doesn't list those tools, and `rm -rf` on a path that doesn't exist does nothing.
- In `build.yml`, set `TMPDIR: ${{ runner.temp }}` on the Docker Scout step. On `ubuntu-26.04`, `/tmp` is a tmpfs with a size quota (systemd ≥ 258), and unpacking the ~3 GB `flutter-android` baseline hit `disk quota exceeded`. `runner.temp` is on the runner's disk.
- Update the `ci-runner-disk-cleanup` spec so the supported Linux runner is `ubuntu-26.04`.

Out of scope:

- The user-facing CI examples (`docs/examples.cue`, `docs/build.mjs`, `examples/*.yml`, `readme.md`) keep `ubuntu-22.04`. They're also used for Gitea and Forgejo runners, where the label means something else, so changing them is a separate decision.

## Impact

- Affected specs: `ci-runner-disk-cleanup` (MODIFIED: runner label in two requirements)
- Affected code: `.github/workflows/*.yml`, `.github/actions/clean-runner-disk/action.yml`
- Risk: the 26.04 image ships newer Docker (29.4.2), Buildx (0.37.1), kernel (7.0) and systemd (259). Its default Java and Python versions may differ too; the June preview changelog lists Java 25 and Python 3.14, but the GA issue lists Java 17. Tools the workflows rely on are pinned through mise, and the images themselves are built from `debian:13-slim`, so the runner OS shouldn't change what ships. The draft PR's CI runs are the check.
