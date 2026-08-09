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
