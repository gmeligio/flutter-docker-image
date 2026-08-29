Two PRs. PR 1 is the fix for #555. PR 2 touches `.github/renovate.json`, which by project
convention ships on a `renovate/reconfigure` branch, so it cannot share a branch with PR 1.

## 1. Repin openjdk (PR 1 — `fix`)

- [x] 1.1 Confirm the target version against the archive, not apt output. **Corrected during apply:** the base-suite `17.0.19+10-1~deb12u2` does NOT build — `bookworm-security` carries `openjdk-17-jre-headless=17.0.20.1+1-1~deb12u1`, and the strict `Depends: (= <same version>)` forces the JDK to match. Correct pin is `17.0.20.1+1-1~deb12u1`
- [x] 1.2 Set `OPENJDK_17_JDK_HEADLESS_VERSION="17.0.20.1+1-1~deb12u1"` in `android.Dockerfile:143`
- [x] 1.3 Verified by `--no-cache` build of the apt layer with bookworm sources: the base-suite version fails with unmet dependencies, `17.0.20.1+1-1~deb12u1` installs and reports `openjdk version "17.0.20.1"`
- [x] 1.4 Opened #558, referencing #555, stating the value was read from the archive and verified by a `--no-cache` build of the apt layer

## 2. Adjust registryUrls (PR 2 — `chore`, branch `renovate/reconfigure`)

- [x] 2.1 Reset the stale local `renovate/reconfigure` onto `origin/main` (its prior content shipped as squash-merged #538; no remote branch, no open PR)
- [x] 2.2 Dropped `trixie-updates`; kept `trixie-security`
- [x] 2.3 Dropped `bookworm-updates`; kept `bookworm-security` — the only installable openjdk version is published there and nowhere else
- [x] 2.4 Both `description` fields record the hardcoded-`Packages.gz` limitation, that `-security` is retained despite 404ing because it states correctly where the pin resolves from, and cite renovatebot/renovate#44330 / PR #35865 as the condition for it resuming
- [x] 2.5 `./script/renovate_validate.sh` passes (syntax only)
- [ ] 2.6 After #559 merges, confirm in the Renovate job log that the `-updates` 404s are gone and pins still resolve *(post-merge; cannot be done before archive)*

## 3. Spec sync

- [x] 3.1 Applied the delta to `openspec/specs/linux-image-package-pinning/spec.md`
- [x] 3.2 Corrected the experience context: it claimed `17.0.20+8-1~deb12u1` was a genuine `bookworm-security` upload and had the two versions swapped. That version was published nowhere
- [x] 3.3 Narrowed the suite mandate from base + `-updates` + `-security` (unsatisfiable) to base + `-security`, and added a scenario recording that the image build catches an uninstallable pin on its own PR
- [ ] 3.4 Close #555 referencing the repin, and note in #536 that the patch half of the hardcoded-`17` collision rots independently of the major *(on merge of #558)*

## 4. Reverted during apply

- [x] 4.1 Built `script/check_deb_pins.sh` + tests + mise tasks + a `build.yml` job, then **removed all of it**: editing a pin invalidates the layer cache and forces `apt-get install` to re-run, so the image build already fails a bad pin on its own PR. Verified directly. See design.md Decision 1
- [x] 4.2 Added a weekly `schedule` to `ci.yml`, then **removed it**: finding a rotted pin on the next PR is the intended workflow. `ci.yml` is byte-identical to `origin/main`
