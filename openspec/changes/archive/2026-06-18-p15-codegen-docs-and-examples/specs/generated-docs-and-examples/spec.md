### Requirement: Docs and examples are regenerated from the version manifest and never drift

`mise run docs` SHALL regenerate `readme.md` and `examples/{github-actions,
gitlab-ci,gitea-actions,forgejo-actions}.yml` from `config/version.json`, and CI
SHALL fail when any committed output differs from a fresh regeneration. The
generated `readme.md` SHALL be the file used both as the GitHub repository README
and as the Docker Hub repository description.

The experience context is the maintainer cutting a Flutter release and the reader
viewing the README/Docker Hub page: the maintainer never hand-edits versions in
the docs, and the reader never sees a version that disagrees with what the image
actually ships.

#### Scenario: Version bump regenerates docs and examples in the same PR

- **GIVEN** `config/version.json` is updated to a new Flutter version
- **WHEN** the `update-version` workflow runs `mise run docs`
- **THEN** `readme.md` and every `examples/*.yml` reflect the new version
- **AND** the regenerated files are part of the same version-bump PR

#### Scenario: Stale committed output fails CI

- **GIVEN** a PR whose committed `readme.md` or `examples/*.yml` does not match a
  fresh `mise run docs`
- **WHEN** the docs-in-sync check runs (`mise run docs` then `git diff --exit-code`)
- **THEN** the check fails with instructions to run `mise run docs`

### Requirement: README presents exact predownloaded versions and ready-to-use examples

`readme.md` SHALL list the exact predownloaded tool versions sourced from
`config/version.json` (Flutter, Fastlane, Gradle, Android NDK, Android build
tools, Android platforms), SHALL include a usage snippet whose image tag equals
the manifest Flutter version, SHALL include GitHub Actions and GitLab CI usage
examples inline, SHALL name all four supported CI platforms (GitHub Actions,
GitLab CI, Gitea, Forgejo) and link to the `examples/` directory, and SHALL
include a generated table of contents.

The experience context is a prospective user reading only the README: they judge
compatibility from the exact tool versions shown inline, copy a working usage
snippet, and learn that non-GitHub CI backends are supported and where to find
runnable examples — without clicking away to `config/version.json`.

#### Scenario: Features list matches the manifest

- **WHEN** `readme.md` is generated
- **THEN** the predownloaded-tool versions it lists equal the corresponding
  values in `config/version.json`

#### Scenario: Usage snippet uses the current tag

- **WHEN** `readme.md` is generated for manifest Flutter version `X.Y.Z`
- **THEN** the usage snippet references the image at tag `X.Y.Z`

#### Scenario: All four platforms are named

- **WHEN** a reader views `readme.md`
- **THEN** GitHub Actions, GitLab CI, Gitea, and Forgejo are all named
- **AND** a link to the `examples/` directory is present

### Requirement: Runnable examples for four CI backends, with Node guidance for non-GitHub runners

The `examples/` directory SHALL contain `github-actions.yml`, `gitlab-ci.yml`,
`gitea-actions.yml`, and `forgejo-actions.yml`, each valid YAML referencing the
current image tag. The Gitea and Forgejo examples SHALL demonstrate making Node
available for JavaScript actions such as `actions/checkout` at the job level, and
the image itself SHALL NOT bundle Node.js.

The experience context is a Gitea or Forgejo user (issue #493) whose build fails
with `Cannot find: node in PATH`: they open the matching example and find a
runnable workflow that makes `actions/checkout` work, while users on GitHub
Actions and GitLab CI (which need no in-image Node) are unaffected and the image
stays minimal.

#### Scenario: Gitea/Forgejo examples provide Node; the image does not

- **GIVEN** the generated `examples/gitea-actions.yml` and
  `examples/forgejo-actions.yml`
- **THEN** each contains a job-level step that makes Node available before
  `actions/checkout` runs
- **AND** neither `android.Dockerfile` nor the published image installs Node.js

#### Scenario: Every example targets the manifest version

- **WHEN** the examples are generated for manifest Flutter version `X.Y.Z`
- **THEN** each `examples/*.yml` references the image at tag `X.Y.Z`

### Requirement: Generation is code-generation from a single source on a minimal toolchain

`readme.md` SHALL be composed by a dependency-free Node program
(`docs/build.mjs`, Node standard library only) from `config/version.json`, with
no MDX, `mdx-bundler`, or `pnpm` docs workspace. The four `examples/*.yml` SHALL
be produced by `cue export` from CUE definitions, using only CUE's evaluation/
export surface (not `cue cmd`, `tools/file`, or `@embed`). `config/version.json`
SHALL remain the single source of truth, validated by `config/schema.cue`.
`windows.md`, `docs/contributing.md`, and `LICENSE.md` SHALL be static committed
markdown.

This guardrail is load-bearing: it is what keeps the docs/examples consistent
with the manifest (no stale versions the reader would notice) and valid by
construction (no malformed example a user would copy), while removing the heavy
MDX/`pnpm` dependency tree whose upkeep the maintainer otherwise pays for in
lockfile churn and CVE remediation (the project already carries an `mdx-bundler`
CVE workaround). Reintroducing a template engine or a heavy doc framework would
restore that cost and the staleness/supply-chain risk this guardrail removes.

#### Scenario: The MDX/pnpm toolchain is absent

- **WHEN** the repository is built
- **THEN** there is no `docs/src` pnpm workspace, MDX source, or `mdx-bundler`
  dependency
- **AND** `mise run docs` generates outputs using only `node` and `cue`
