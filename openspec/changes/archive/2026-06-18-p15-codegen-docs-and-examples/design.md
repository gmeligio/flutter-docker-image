## Approach

Two code generators, one source of truth, wired into the existing `mise run docs`
task and the existing regenerate-and-diff CI gate.

```
  config/version.json  ── single source (CUE-validated by config/schema.cue)
        │
        ├─ node docs/build.mjs ───────────────▶ readme.md   (GitHub README + Docker Hub desc)
        │     compose markdown in code:
        │     features (exact versions), usage snippet (current tag),
        │     GitHub+GitLab examples, 4-platform mention + examples/ link,
        │     generated TOC, channel badge
        │
        └─ cue export docs/examples.cue config/version.json -e <backend> --out yaml ▶ examples/<backend>.yml  (×4)
              github-actions, gitlab-ci, gitea-actions, forgejo-actions

  windows.md / docs/contributing.md / LICENSE.md  → static committed markdown
```

### Why code generation, not templating (and not MDX)

MDX already *is* code generation (it compiles to JS that runs to emit markdown),
so the issue with it is not the model but the **dependency weight** (`mdx-bundler`/
`esbuild`/`pnpm`, with a standing `mdx-bundler` CVE workaround). The replacement
keeps the code-generation model on a minimal toolchain:

- **`docs/build.mjs`** composes the markdown by executing code (template literals,
  `.map().join()`, a TOC function) — no separate template document, no
  substitution engine. Node stdlib only; `node` is already mise-pinned.
- **CUE** emits the examples as data → YAML via `cue export --out yaml`
  (valid-by-construction). Only the **mature** surface is used; `cue cmd`/
  `tools/file`/`@embed` are avoided (less stable; `cmd`+`@embed` has a known
  upstream issue). The `mise` task does the file writing via shell redirection.

### TOC: hand-rolled, no dependency

A ~10-line function derives the `## Contents` list from `##`/`###` headings using
GitHub anchor slugs. Chosen over `markdown-toc`/`doctoc` because the task is tiny
and stable, the headings are controlled (simple, unique), and a dependency would
reintroduce the lockfile/update/CVE surface this change is removing. If headings
ever need duplicate/unicode handling, swapping in a library is a localized change.

### Node-for-`actions/checkout` in the Gitea/Forgejo examples (#493)

GitHub mounts Node at `/__e`; GitLab CI clones itself (no checkout action); only
act-based runners (Gitea/Forgejo) need Node inside a custom `container.image`.
The Gitea/Forgejo examples therefore include a job-level step that provisions
Node before `actions/checkout` (e.g., a rootless install into `$HOME`, runnable
under the image's non-root `flutter` user). The image is **not** modified.

### Placeholder safety in the Node generator

`build.mjs` composes strings directly, so there is no `{{…}}` placeholder syntax
to collide with GitHub Actions `${{ … }}` inside the inlined example blocks. Bad
field access surfaces as a JS error at build time (and CUE validates
`version.json` upstream), so a missing value fails the build rather than emitting
a literal token.

## Automated Test Strategy

- **Migration parity (pre-merge, decisive):** run `mise run docs` and `git diff`
  the generated `readme.md` against the current committed `readme.md`. Content
  must be equivalent (allowing intentional additions: the four-platform mention +
  `examples/` link). This proves the Node generator reproduces the MDX output.
- **In-sync gate (CI, ongoing):** `update-docs.yml` runs `mise run docs` then
  `git diff --exit-code` — now covering `readme.md` and `examples/`. Stale output
  or a generator bug fails the required check.
- **Example validity:** `cue export` only emits well-formed YAML; additionally,
  each example is verified to be a runnable workflow for its backend
  (structurally, and for Gitea/Forgejo that `actions/checkout` succeeds with the
  provisioned Node) before merge.
- **Version freshness:** covered by `update-version.yml` (already runs
  `mise run docs`); a bump regenerates `readme.md` + `examples/` in the same PR.
- No new test framework: the generators are plain `node`/`cue`, exercised by the
  existing CI gate.

## Observability

- `build.mjs` logs `📝 readme.md` on success and **exits non-zero** on any
  failure (missing manifest field, write error) — no silent partial output.
- `cue export` fails loudly on an invalid `docs/examples.cue` definition; the `mise` task
  aborts on the first non-zero command, so a broken example fails the run.
- The CI `git diff --exit-code` step is the catch-all: any divergence between
  committed `readme.md`/`examples/` and a fresh build fails the required check
  with instructions to run `mise run docs`. A stale doc cannot merge silently.
