## 1. Node docs generator (`readme.md`)

- [x] 1.1 Add `docs/build.mjs` (Node stdlib only): read `config/version.json`,
  build a single `values` object (flutter, fastlane, gradle, ndk, build-tools,
  platforms-joined, derived dockerHub/ghcr/quay URIs, channel + badge URL).
- [x] 1.2 Compose `readme.md` in code, reproducing the current sections: title,
  generated `## Contents` TOC, Features (exact versions), Running Containers
  (registry table + inline **GitHub Actions** and **GitLab CI** examples + image
  tag), Fastlane, Tags, Building Locally, Roadmap, FAQ, Contributing, License,
  plus badges. Add a sentence naming all four CI platforms (GitHub Actions,
  GitLab CI, Gitea, Forgejo) with a link to `examples/`.
- [x] 1.3 Hand-rolled TOC: derive `## Contents` from `##`/`###` headings via
  GitHub anchor slugs; exclude the Contents heading itself.
- [x] 1.4 Emit the auto-generated banner comment; `writeFileSync('readme.md')`;
  log success and exit non-zero on any failure.

## 2. CUE example generation (`examples/*.yml`)

- [x] 2.1 Add `docs/examples.cue` defining four workflows as data, fed by
  `config/version.json` values: `github`, `gitlab`, `gitea`, `forgejo`.
- [x] 2.2 `github`/`gitlab` mirror the README usage examples at the current tag.
- [x] 2.3 `gitea`/`forgejo` include a job-level step that provisions Node for
  `actions/checkout` (rootless, runnable as the image's `flutter` user). Do NOT
  modify `android.Dockerfile` — the image bundles no Node.
- [x] 2.4 Generate via `cue export docs/examples.cue config/version.json -e <backend> --out yaml > examples/<file>.yml`
  for each backend (mature surface only — no `cue cmd`/`tools/file`/`@embed`).

## 3. Wire into `mise run docs` and retire MDX

- [x] 3.1 Update `mise.toml` `docs` task `run` to: `node docs/build.mjs` + the
  four `cue export …` commands. Remove the `pnpm install`/`pnpm run build` steps.
- [x] 3.2 Remove `pnpm` from `mise.toml` `[tools]` if unused after the change.
- [x] 3.3 Delete `docs/src/` (`*.mdx`, `compile.js`, `package.json`,
  `pnpm-lock.yaml`, `pnpm-workspace.yaml`).
- [x] 3.4 Convert `windows.md`, `docs/contributing.md`, `LICENSE.md` to static
  committed markdown (their current generated content, kept as-is).

## 4. Workflows and CI gate

- [x] 4.1 `build.yml` `build-docs`: run `mise run docs` (via the existing mise
  setup) instead of `pnpm install`/`pnpm run build`; keep uploading the outputs.
- [x] 4.2 `update-docs.yml`: change `paths:` from `docs/src/**` to the new sources
  (`docs/build.mjs`, `docs/examples.cue`, `config/version.json`); update the header comment.
  The check/generate jobs keep using `mise run docs` + `git diff`.
- [x] 4.3 Confirm the in-sync `git diff --exit-code` now covers `readme.md` **and**
  `examples/` (it does, since `mise run docs` regenerates both).
- [x] 4.4 `update-version.yml`: no change needed (already calls `mise run docs`);
  confirm the bumped README tag + examples regenerate in its PR.
- [x] 4.5 Docker Hub: no change — `release.yml` `update-description` still uses
  `readme.md`.

## 5. Verify

- [x] 5.1 Migration parity: run `mise run docs`; `git diff` the new `readme.md`
  against the previous committed `readme.md`; confirm content is equivalent aside
  from the intended additions (four-platform mention + `examples/` link).
- [x] 5.2 Confirm `examples/*.yml` are valid YAML at the current tag; structurally
  validate each as a runnable workflow; confirm `gitea`/`forgejo` provision Node
  and `actions/checkout` would succeed; confirm the image still has no Node.
- [ ] 5.3 Confirm the docs-in-sync CI check passes on a no-op PR and fails when an
  output is deliberately edited out of sync.

## 6. Archive

- [ ] 6.1 After merge, sync the `generated-docs-and-examples` spec to shipped
  behavior and move this change to
  `openspec/changes/archive/<YYYY-MM-DD>-p15-codegen-docs-and-examples/`.
- [ ] 6.2 Close #493 referencing the shipped `examples/` (Gitea/Forgejo Node
  guidance; image unchanged).
