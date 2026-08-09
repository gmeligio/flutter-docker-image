# Pre-refactor baseline (task 1.1)

Captured 2026-08-09 from real CI runs, to diff each leg's resolved
`docker buildx build` command line against after the refactor.

**Do not use run `31194164846`** (referenced in the original design). It predates
PR #537 and shows only six build args.

## Build arguments — identical across every Linux leg

All seven, in this order:

```
--build-arg flutter_version=3.44.9
--build-arg fastlane_version=2.237.0
--build-arg android_java_version=17
--build-arg android_build_tools_version=36.0.0
--build-arg android_platform_versions=36
--build-arg android_ndk_version=28.2.13676358
--build-arg cmake_version=3.22.1
```

Manifest at `f006815` / `config/version.json`. `android_java_version=17` is the
value PR #537 wired; its presence is what makes this baseline current.

## Per-leg distinguishing flags

Source runs: `build.yml` → `31313920183` (PR event, `731d39d`);
`ci.yml` → `31314363759` (main, `f006815`).

| Leg | target | cache | output | attestations |
|---|---|---|---|---|
| `build.yml` push, android | `android` | `type=registry,ref=ghcr.io/gmeligio/flutter-android:buildcache` (+`mode=max` on `cache-to`) | `--push` | `provenance,mode=max` + `sbom` |
| `build.yml` push, web | `web` | `type=registry,ref=ghcr.io/gmeligio/flutter-web:buildcache` (+`mode=max`) | `--push` | `provenance,mode=max` + `sbom` |
| `ci.yml` | `android` | `type=gha` (+`mode=max` on `cache-to`) | `--load` | none |
| `build.yml` fork | `android` | not captured — see below | `--load` (artifact handoff) | none |
| `release.yml` | `android`, `web` | not captured — see below | `--push` | see below |

The cache ref is **per target** (`flutter-android` vs `flutter-web`), so
`cache-backend` alone is insufficient as an input — the ref must be derived from
the image name. Task 1.4 must account for this.

## Two legs not captured, and why

- **`build.yml` fork path** — requires a PR from a fork; none in recent history.
  Its build-args block is byte-identical to the push path in the source
  (`build.yml:181-188` vs `:158-164`), so the seven args are known; only the
  output mode differs. Verify at task 3.4 against the source, not a run.
- **`release.yml`** — the latest run (`31194203112`) is at `0bc825f`, which
  predates PR #537 and shows **six** args. Not a valid baseline. Its block is
  byte-identical to the others in the source (`release.yml:114-121`), so the
  expected set is the seven above. Verify at task 4.2 against the source, and
  against the first real release run after this lands.

This gap is why task 5.1's source-level grep matters: for two of the five legs it
is the only pre-merge check available.

## Post-refactor confirmation (run 31318147664, PR #540)

Run-level diff of the resolved `docker buildx build` command line, captured after
the switch. Both `build.yml` push legs:

| Leg | build-args | target | output | cache |
|---|---|---|---|---|
| web | 7, identical to baseline (order + values) | `web` | `--push` | `type=registry,ref=ghcr.io/gmeligio/flutter-web:buildcache` (+`mode=max`) |
| android | 7, identical to baseline (order + values) | `android` | `--push` | `type=registry,ref=ghcr.io/gmeligio/flutter-android:buildcache` (+`mode=max`) |

Attestations present on both, as before. The emitter's new log group appears in
each build job:

```
##[group]Versions read from config/version.json
FLUTTER_VERSION=3.44.9
...
##[endgroup]
```

All 11 jobs in the run succeeded, including `Test image` and `Scan image` for
both images — which confirms the fork-handoff outputs and the SBOM attestation
path still work through the shared action.

Still verified against source only, per the gaps noted above: the `build.yml`
fork path (needs a fork PR) and `release.yml` (runs only on release).
