## 1. Declare the image set

- [x] 1.1 Create `config/images.json` with one entry per published image — `flutter-android`, `flutter-web`, `flutter-linux`, `flutter-windows` — each carrying `name`, `dockerfile`, `shortDescription`, `scout`, `prTag`, plus `target` and `testConfig` on the three `android.Dockerfile` images. Copy `shortDescription` for `flutter-windows` from its live Docker Hub value (`"Docker images for Flutter CI in Windows platform"`); use the GitHub repo description for the other three, preserving today's behavior.
- [x] 1.2 Add an `#Images` definition to `config/schema.cue` using the `dockerfile` discriminator from design decision 2, requiring `target` and `testConfig` when `dockerfile == "android"` and pinning `scout: false` / `prTag: false` when `dockerfile == "windows"`.
- [x] 1.3 Extend `.github/actions/validate-version-manifest` to also run `cue vet config/schema.cue -d '#Images' config/images.json`.
- [x] 1.4 Verify the schema rejects the negative cases: a `dockerfile: "android"` entry missing `target` or `testConfig` fails with "field is required but not present"; a `dockerfile: "windows"` entry setting `scout: true` fails with "conflicting values false and true". Verify a correct manifest passes.

## 2. Fix the description sync (issue #521)

- [x] 2.1 Add a `setup`-style job to `release.yml` that reads `config/images.json` and emits filtered matrices as `fromJSON` outputs, following the existing pattern at `build.yml:22-27`. Keep matrix key names (`name`, `target`, `config`) so downstream `matrix.*` references need no edits.
- [x] 2.2 Fail the setup job when any filter yields an empty list, and log each constructed matrix so a run records which images it acted on.
- [x] 2.3 Point `update-description`'s matrix at the manifest (all images) and pass `short-description` from each entry's `shortDescription` instead of `github.event.repository.description`.
- [x] 2.4 Change `update-description`'s `needs: release-linux` to `needs: [release-linux, release-windows]`, keeping `if: !cancelled()`.
- [x] 2.5 Point `record-image`'s matrix at the manifest filtered on `scout`, so it still yields exactly three images — now by declaration rather than by omission.
- [x] 2.6 Point `release-linux`'s build matrix and `verify-published`'s matrix at the manifest (`dockerfile == "android"` and all images respectively), confirming the rendered job names are unchanged.

## 3. Retire the remaining enumerations (issue #544)

- [x] 3.1 Add a manifest-reading setup step or job output to `build.yml` supplying the same filtered matrices.
- [x] 3.2 Convert `build.yml`'s build matrix (`:52-57`) to `dockerfile == "android"`.
- [x] 3.3 Convert `build.yml`'s test matrix (`:215-220`) to the images declaring `testConfig`, mapping `config` from that field.
- [x] 3.4 Convert `build.yml`'s scan matrix (`:290-292`) to the images declaring `scout`.
- [x] 3.5 Convert `cleanup-pr-image.yml`'s matrix (`:33-35`) to the images declaring `prTag`, and update its comment to point at the manifest as the reason Windows is absent.
- [x] 3.6 Confirm on this PR's own run that `build.yml`'s build, test, and scan legs each still enumerate exactly three images with unchanged leg names.

## 4. Docs generation

- [x] 4.1 Change `docs/build.mjs` to read the image list from `config/images.json` instead of the literal at `:44`.
- [x] 4.2 Add `config/images.json` to `update-docs.yml`'s `paths:` filter (`:18`) so an image-set-only change still triggers the drift check.
- [x] 4.3 Run `mise run docs` and confirm `readme.md` is byte-identical — this change alters the generator's input source, not its output, so any diff is a defect.

## 5. Specs

- [x] 5.1 Add the `published-image-set` and `docker-hub-description-sync` specs under `openspec/specs/`.
- [x] 5.2 Apply the deltas to `generated-docs-and-examples` (drop the three-image enumeration and the Docker Hub description clause, which moves to the new sync spec), `ci-image-vulnerability-scan` (per-image Scout declaration), `ci-image-handoff` (generalize off `flutter-android`), and `ci-image-anonymous-availability` (derive the verified set from the manifest).
- [x] 5.3 Correct the stale `release-android` / `needs: release-android` references in `windows-image-release/spec.md:65,82`, which the workflow renamed to `release-linux`.

## 6. Verification and handoff

- [ ] 6.1 Confirm `openspec validate sync-published-image-descriptions` passes and CI is green on the PR.
- [ ] 6.2 Open the PR as `fix(ci): sync published image descriptions from a declared image set`, closing #521 and #544, and note that the archived description trade-off (`archive/2026-05-20-p2-release-windows-image/design.md:66`) is reversed because its premise expired, while the adjacent Scout trade-off (`:67`) is upheld.
- [ ] 6.3 After the next tag, confirm `full_description` is non-null for `flutter-windows` and `flutter-linux`, and that `flutter-windows`'s short description still reads `"Docker images for Flutter CI in Windows platform"`.
- [ ] 6.4 Open a follow-up issue for per-image Docker Hub descriptions, so each image's page stops describing all four.
