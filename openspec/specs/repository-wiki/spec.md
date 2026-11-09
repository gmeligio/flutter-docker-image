# repository-wiki Specification

## Requirements

### Requirement: README exposes a DeepWiki entry point

The README SHALL display a DeepWiki badge in the header badge row that links to `https://deepwiki.com/gmeligio/flutter-docker-image`, so a CI engineer reading the repo on GitHub or Docker Hub can reach the AI-generated wiki in one click.

The badge SHALL be authored in `docs/build.mjs` (the generator for `readme.md`) so regenerating the docs keeps `readme.md` in sync.

#### Scenario: Reader on GitHub clicks through to the wiki

- **GIVEN** a CI engineer is reading `readme.md` on GitHub
- **WHEN** they click the DeepWiki badge in the header
- **THEN** the browser navigates to the project's DeepWiki page
- **AND** the page renders the auto-generated wiki for this repository

#### Scenario: Regenerating docs preserves the badge

- **GIVEN** the maintainer edits `docs/build.mjs` or `config/version.json`
- **WHEN** they run `mise run docs`
- **THEN** the regenerated `readme.md` still contains the DeepWiki badge in the header badge row

### Requirement: Wiki refreshes automatically when the repository changes

The repository SHALL opt into DeepWiki's badge-driven auto-refresh behavior so that the wiki a reader sees stays in step with the current state of `main` without any manual maintainer action.

The opt-in mechanism SHALL be the presence of the DeepWiki badge in `readme.md` (the same badge required above).

#### Scenario: Reader after a merge sees current content

- **GIVEN** a change has been merged to `main` that modifies `android.Dockerfile` or `windows.Dockerfile`
- **WHEN** a reader visits the project's DeepWiki page after the next refresh cycle
- **THEN** the wiki content reflects the merged change (no manual rebuild step required from the maintainer)

### Requirement: Contributors are told how the wiki works

`docs/contributing.md` (a static committed Markdown file) SHALL include a short section pointing contributors at the DeepWiki and explaining that the badge in the README is what keeps the wiki fresh.

#### Scenario: New contributor opens contributing.md

- **GIVEN** a new contributor opens `docs/contributing.md`
- **WHEN** they read through the document
- **THEN** they find a section that names DeepWiki, links to the wiki URL, and explains that the README badge enables auto-refresh
