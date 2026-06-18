## Why

The committed docs (`readme.md`, `windows.md`, `docs/contributing.md`, `LICENSE.md`)
are produced by an MDX toolchain — `docs/src/*.mdx` compiled by `mdx-to-md`
(`mdx-bundler` + `esbuild`) inside a `pnpm` workspace, with `remark-gfm` and
`remark-toc`. The **only** dynamic work this machinery does is inject a handful
of values from `config/version.json` into markdown (Flutter/Fastlane/Gradle/NDK/
build-tools/platforms versions + the image tag) and build a table of contents.
That is a large, churning dependency surface for variable substitution — and it
carries ongoing upkeep: `docs/src/pnpm-workspace.yaml` already documents a
workaround for **CVE‑2026‑41907 in `mdx-bundler@10.1.1`**.

Separately, [#493](https://github.com/gmeligio/flutter-docker-image/issues/493):
consumers on non-GitHub Actions runners (Gitea/Forgejo) hit
`Cannot find: node in PATH` because `actions/checkout` is a JavaScript action and
those runners do not mount Node into a custom `container.image` (GitHub does, at
`/__e`; GitLab CI clones itself and needs no checkout action). We deliberately
will **not** bundle Node into the image — it would add CVE/SBOM/size cost to
100% of users (GitHub + GitLab structurally need nothing) to serve a ~0.02%
niche — and we will **not** maintain a helper script. The agreed resolution is to
ship runnable per-backend usage **examples**, with the Gitea/Forgejo ones
demonstrating how to provide Node at the job level. There is no `examples/`
directory today, and usage snippets exist inline for GitHub + GitLab only.

This change re-platforms documentation and examples onto **code generation**
(not templating, not MDX): a dependency-free Node program composes `readme.md`
from `config/version.json`, and CUE emits the example workflow files. It is
justified for a spec because it changes what two audiences notice: the
**maintainer's** docs build loses its heaviest dependency tree (and the CVE
upkeep that comes with it) while gaining a guarantee that docs/examples never go
stale; and the **image consumer** gains an `examples/` set covering four CI
backends — closing #493 for Gitea/Forgejo without changing the image.

## What Changes

- **Retire the MDX docs toolchain.** Delete `docs/src/` (`*.mdx`, `compile.js`,
  `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`) and drop `pnpm` from
  `mise.toml` (used only by the docs build).
- **`docs/build.mjs` (new, Node stdlib only).** Imports `config/version.json` and
  composes `readme.md` by code: Features list with **exact** predownloaded tool
  versions; a usage snippet whose image tag is the current Flutter version;
  GitHub Actions + GitLab CI examples inline; a sentence naming all four
  supported CI platforms (GitHub Actions, GitLab CI, Gitea, Forgejo) with a link
  to `examples/`; a generated table of contents (hand-rolled, no dependency);
  the channel badge URL derived from `version.json`. `readme.md` continues to
  serve both the GitHub README and the Docker Hub description.
- **`windows.md`, `docs/contributing.md`, `LICENSE.md` become static** committed
  markdown (they carry no `version.json` values today — `windows.mdx` only
  *points to* the manifest in prose).
- **CUE example generation.** A `gen` CUE package defines the four backend
  workflows as data; `cue export --out yaml` emits
  `examples/{github-actions,gitlab-ci,gitea-actions,forgejo-actions}.yml` at the
  current image tag. The Gitea and Forgejo examples include a job-level step that
  makes Node available for `actions/checkout`; the image is unchanged (no Node).
  Only CUE's mature surface is used (`cue export`) — no `cue cmd`/`tools/file`/
  `@embed`.
- **Wire into `mise run docs`.** Replace the `pnpm` build with
  `node docs/build.mjs` + the per-backend `cue export` commands.
- **Workflows.** Point `build.yml`'s `build-docs` job at `mise run docs`; update
  `update-docs.yml` `paths:` to watch the new sources (`docs/build.mjs`, `gen/**`,
  `config/version.json`) instead of `docs/src/**`; `update-version.yml` is
  unchanged (it already calls `mise run docs`, so the README tag and examples
  refresh automatically on a version bump).
- **CI gate.** The existing "`mise run docs` then `git diff --exit-code`" check
  now covers `readme.md` **and** `examples/` (any drift fails CI).
- **No image change. No `version.json` change** (still the single source,
  CUE-validated by `schema.cue`). Examples are valid-by-construction YAML from
  `cue export`; they are **not** `gx`-linted (`gx` only scans `.github/workflows`
  — tracked by [gmeligio/gx#108](https://github.com/gmeligio/gx/issues/108)).

## Capabilities

### New Capabilities

- `generated-docs-and-examples`: the contract that `readme.md` and the four
  `examples/*.yml` are code-generated from `config/version.json` (never drift),
  what the README presents (exact versions, usage snippet, GitHub+GitLab
  examples, four-platform mention, TOC), and that runnable examples exist for
  four CI backends — the Gitea/Forgejo ones providing Node for `actions/checkout`
  without the image bundling Node (resolving #493).

## Impact

- **Affected**: `docs/build.mjs` (new), `gen/*.cue` (new), `examples/*.yml` (new,
  generated), `readme.md` (now Node-generated), `mise.toml`, `.github/workflows/`
  (`build.yml`, `update-docs.yml`); deletions under `docs/src/`. `windows.md`/
  `docs/contributing.md`/`LICENSE.md` demoted to static.
- **Resolves** #493 (Gitea/Forgejo guidance via examples; image keeps no Node).
- **Breaking** (maintainer-facing): the `docs/src` pnpm workspace is removed;
  contributors edit `docs/build.mjs` / `gen/*.cue` instead of `*.mdx`.
- **Behavioral change for readers**: `readme.md`/Docker Hub description content is
  equivalent (exact versions, badges, TOC) plus a four-platform mention and an
  `examples/` link; the usage tag stays current automatically.
- **Risk**: the migration must reproduce the current `readme.md` content — verify
  by diffing the generated output against the existing committed `readme.md`
  before merge. Hand-rolled TOC assumes simple, unique headings (true today).
- **Risk**: `cue export` YAML shape for each backend must match a real, working
  workflow — verify by running each example on its platform / structurally.
- **Out of scope**: `gx` coverage of `examples/` (needs gx#108); any change to
  the image contents; baking Node.
