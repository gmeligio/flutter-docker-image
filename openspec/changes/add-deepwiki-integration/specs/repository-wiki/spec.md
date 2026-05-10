## ADDED Requirements

### Requirement: README exposes a DeepWiki entry point

The README SHALL display a DeepWiki badge in the header badge row that links to `https://deepwiki.com/gmeligio/flutter-docker-image`, so a CI engineer reading the repo on GitHub or Docker Hub can reach the AI-generated wiki in one click.

The badge SHALL be authored in `docs/src/badges.mdx` (the source for the existing MDX→MD pipeline) so a recompile keeps `readme.md` in sync.

#### Scenario: Reader on GitHub clicks through to the wiki

- **GIVEN** a CI engineer is reading `readme.md` on GitHub
- **WHEN** they click the DeepWiki badge in the header
- **THEN** the browser navigates to the project's DeepWiki page
- **AND** the page renders the auto-generated wiki for this repository

#### Scenario: Recompiling docs preserves the badge

- **GIVEN** the maintainer edits any source file under `docs/src/`
- **WHEN** they run the docs compile script
- **THEN** the regenerated `readme.md` still contains the DeepWiki badge in the header badge row

### Requirement: Wiki structure reflects the repository's actual shape

The repository SHALL provide a `.devin/wiki.json` configuration that steers DeepWiki's page generation so the wiki visible to readers covers the load-bearing concerns of this project (android image, windows image, MDX docs pipeline, OpenSpec workflow, release/CI pipeline) rather than a generic auto-outline.

The configuration SHALL declare `repo_notes` describing the project's structure and SHALL declare a `pages` outline naming the top-level pages the maintainer wants to appear.

#### Scenario: Reader looking for windows-specific behavior finds a dedicated page

- **GIVEN** a reader has navigated to the project's DeepWiki
- **WHEN** they browse the page outline
- **THEN** a page covering the Windows image (built from `windows.Dockerfile` and `windows.yml`) is present and distinguishable from the Android image page

#### Scenario: Configuration stays under repository version control

- **GIVEN** the wiki configuration exists at `.devin/wiki.json`
- **WHEN** a contributor inspects the repository
- **THEN** `.devin/wiki.json` is tracked by git (not gitignored)
- **AND** the file is valid JSON parseable by `node -e "JSON.parse(require('fs').readFileSync('.devin/wiki.json'))"`

### Requirement: Wiki refreshes automatically when the repository changes

The repository SHALL opt into DeepWiki's badge-driven auto-refresh behavior so that the wiki a reader sees stays in step with the current state of `main` without any manual maintainer action.

The opt-in mechanism SHALL be the presence of the DeepWiki badge in `readme.md` (the same badge required above).

#### Scenario: Reader after a merge sees current content

- **GIVEN** a change has been merged to `main` that modifies `android.Dockerfile` or `windows.Dockerfile`
- **WHEN** a reader visits the project's DeepWiki page after the next refresh cycle
- **THEN** the wiki content reflects the merged change (no manual rebuild step required from the maintainer)

### Requirement: Contributors are told how the wiki works

`docs/contributing.md` (compiled from `docs/src/contributing.mdx`) SHALL include a short section pointing contributors at the DeepWiki, naming the configuration file (`.devin/wiki.json`), and explaining that the badge in the README is what keeps the wiki fresh.

#### Scenario: New contributor opens contributing.md

- **GIVEN** a new contributor opens `docs/contributing.md`
- **WHEN** they read through the document
- **THEN** they find a section that names DeepWiki, links to the wiki URL, and identifies `.devin/wiki.json` as the file to edit if the page outline needs to change
