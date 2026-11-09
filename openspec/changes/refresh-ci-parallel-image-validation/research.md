# Research: refresh ci-parallel-image-validation spec (#597)

Source: https://github.com/gmeligio/flutter-docker-image/issues/597. Base: origin/main `56aab94`.

## Context

PR pipeline in `.github/workflows/build.yml`:

```
setup ──(matrix from config/images.json: build / test / scout)──┐
  │                                                              │
  ▼                                                              │
build-image  "Build and push image (<name>)"  :71-72             │
  │  handoff: GHCR pr-<N> tag | fork: artifact image-<run_id>-<name> (:223)
  ├──────────────▶ test-image  "Test image (<name>)"  :228-229   │ per image
  └──────────────▶ scan-image  "Scan image (<name>)"  :294-300   │ fork-gated (job if)
```

Specs describing that chain:

| Spec | Owns | Status |
|---|---|---|
| ci-image-handoff | build → consumer handoff | Purpose says "`test_image` job" (:5); `image_artifact = image-<run_id>` (:14) stale |
| ci-image-build-cache | cache backend | 3 underscore keys |
| ci-parallel-image-validation | test ∥ scan | no Purpose; 23 underscore keys; single-image; migration req |
| ci-image-vulnerability-scan | scan policy | already assumes fork gate (:25) |
| ci-workflow-readability | kebab id + Title Case `name:` (:31) | 1 underscore key |

## Findings

1. **Model: job keys used as identities.** Spec keys requirements on `build_image`/`test_image`/`scan_image` (spec.md:5,13,24,57). User-visible and ruleset-required identity is the check display name: main ruleset requires `Test image (flutter-android|flutter-linux|flutter-web)`, not job keys (`gh api repos/gmeligio/flutter-docker-image/rules/branches/main`). Key/name convention owned by ci-workflow-readability:31.
2. **Model: single image.** `ghcr.io/<owner>/flutter-android:pr-<N>` (spec.md:32), `image-<run_id>` (:39), `max(test, scan)` timing (:20). CI is a per-image matrix; test set and Scout set differ (build.yml:28-29,50-66).
3. **Duplication.** Req 2 "consumers don't rebuild" (spec.md:22-40) restates ci-image-handoff. Req 3 fork gate (spec.md:42-53) restates ci-image-vulnerability-scan:25 / handoff fork scenario.
4. **Migration in living spec.** Req 4 (spec.md:55-75) is a one-time rename plan. Rename already happened (`fddd298`, #477). Same smell in ci-workflow-readability:50-56 ("in this change").
5. **Only unique content:** test and scan run in parallel per image after build.
6. **Structure: no gate.** No CI runs `openspec validate` (gx.yml:5-9 paths; mise.toml has no task) → #598. Archive sync only applies deltas; direct workflow refactors never produce one. config.yaml rules target a "desktop user" → let migration req pass → #599. Missing Purpose across 5 specs → #561.

```
spec drift sources
  workflow refactor (no delta) ──▶ specs stale
  archive sync (delta only)    ──▶ only touched reqs refreshed
  no validate in CI            ──▶ structural errors land
  wrong audience in config     ──▶ migration reqs accepted
```

## Options

| Option | Pros | Cons |
|---|---|---|
| A. Refresh in place: add Purpose, kebab keys, drop req 4 | Smallest diff; closes #597 literally | Keeps duplication with handoff/scan specs; still single-image model |
| B. Fold into ci-image-handoff: move "test ∥ scan per image" req there, delete ci-parallel-image-validation, fix handoff's stale names | One spec per chain; removes duplication; check-name model | Removes a capability (breaking spec layout); touches 2 specs |
| C. New `pr-image-pipeline` spec merging handoff + parallel validation | Cleanest name for the whole chain | Largest diff; renames a spec others reference |

```
A                          B
handoff ─┐                 handoff (+ parallel req, check names, per-image)
parallel ─┼ (overlap)      scan (fork gate)
scan ────┘                 [parallel spec removed]
```

## Recommendation

**B.** One change, `refresh-ci-parallel-image-validation`:
- REMOVED: ci-parallel-image-validation (all 4 reqs).
- MODIFIED ci-image-handoff: Purpose → `build-image`; artifact `image-<run_id>-<name>`; outputs match build.yml (`is_fork`, `tag`, :88,244-245); ADDED req "Test and scan validate each image in parallel after build", phrased by check display names (`Test image (<name>)`, `Scan image (<name>)`).
- Fix remaining underscore keys in ci-image-build-cache, ci-workflow-readability.
- Leave strict-warning cleanup (#561 covers Purpose for other specs), CI gate (#598), config audience (#599) to their issues.

## Next steps

`/opsx:propose refresh-ci-parallel-image-validation`.
