# Validation: remove dead version machinery

Verified in the review fork against baseline `f7604a7ce65798491a67df74199027bbcd59b52c`.
The existing static command-line-tools assertion was preserved; no generator hardening or `.env.example` changes were added.

## Full Android suite

- Image: `ghcr.io/gmeligio/flutter-android:3.47.2`, matching `config/version.json`.
- Local image ID: `29eaa617fa06d1631d8aa2b3fd31ecc03a217000b685fcc34d303298126926b4`.
- Container Structure Test: `1.22.1`.

```sh
DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock" \
  timeout --signal=TERM --kill-after=30s 1200s \
  container-structure-test test \
    --image ghcr.io/gmeligio/flutter-android:3.47.2 \
    --config test/android.yml --output json \
    --test-report "$DELTA_SCRATCH_DIR/android-3.47.2-report.json"
```

Result: **10 passed, 0 failed, 10 total**, in **170.84 seconds**.
All eight command tests and both file-content tests passed, including the Gradle release build, Fastlane execution, exact command-line-tools revision, and analytics check.
The earlier execution limit was not a test failure; this run completed with a longer outer deadline.

## Static expectation and generation

- Compared `test/android.yml` with `git show HEAD:test/android.yml` using `cmp`: identical.
- Ran `./script/update_test.sh` twice and repeated the comparison after each run: identical.
- Ran the original command-line-tools file-content assertion against a scratch-only revision `23.0` fixture using Container Structure Test's host driver: one expected failure, confirming that the reviewed-revision gate remains.
- The negative fixture contained no command tests and did not modify the repository fixture.

## Other checks

- Both `cue vet` checks passed for `#Version` and `#Images`.
- `sh -n script/update_test.sh` passed.
- Ran all five documentation-generation commands declared by `tasks.docs`: no changes to `readme.md` or `examples/`.
- `gx lint` reported no issues.
- Compared all environment exports with and without the initial `30.0.3` default: identical.
- Searches outside historical archives and proposal documents found no live references to the removed scripts, cmdline-tools tags, or workflow defaults.
- All relocated proposal document link targets resolved.
- `git diff --check` passed.
- `test/android.yml`, `android.Dockerfile`, `.env.example`, and `.github/renovate.json` remained unchanged.

## Scope boundary

The full suite ran against the matching published image, not a fresh build from this checkout.
Dockerfile installation and build-argument values are unchanged; no Windows build or hosted GitHub Actions run was performed.
