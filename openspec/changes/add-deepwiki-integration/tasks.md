## 1. README badge

- [ ] 1.1 Add a DeepWiki badge to `docs/src/badges.mdx` linking to `https://deepwiki.com/gmeligio/flutter-docker-image`, using the same Shields-style markup as the surrounding badges
- [ ] 1.2 Run `npm run readme` (and `npm run build`) inside `docs/src/` to regenerate `readme.md`
- [ ] 1.3 Confirm the regenerated `readme.md` carries the DeepWiki badge in the header badge row and commit both files

## 2. Wiki configuration

- [ ] 2.1 Create `.devin/` and add `.devin/wiki.json` with a `repo_notes` array describing: the android vs windows image split, the MDX→MD docs pipeline (`docs/src/` → `readme.md`, `docs/*.md`), the OpenSpec workflow (`openspec/`), and the release/CI pipeline (`.github/workflows/`)
- [ ] 2.2 Populate `pages` with a curated outline covering at least: Overview, Android image, Windows image, Building locally, Docs pipeline, Release & CI, OpenSpec workflow
- [ ] 2.3 Validate the file with `node -e "JSON.parse(require('fs').readFileSync('.devin/wiki.json','utf8'))"`
- [ ] 2.4 Confirm `.gitignore` does not exclude `.devin/`; commit the file

## 3. Contributing docs

- [ ] 3.1 Add a "Repository wiki" section to `docs/src/contributing.mdx` that names DeepWiki, links to `https://deepwiki.com/gmeligio/flutter-docker-image`, identifies `.devin/wiki.json` as the steering file, and explains that the README badge is what enables auto-refresh
- [ ] 3.2 Run `npm run contributing` to regenerate `docs/contributing.md`
- [ ] 3.3 Commit `docs/src/contributing.mdx` and `docs/contributing.md` together

## 4. Verification

- [ ] 4.1 Re-read the regenerated `readme.md` on GitHub's preview and confirm the DeepWiki badge renders and links correctly
- [ ] 4.2 After merge to `main`, open `https://deepwiki.com/gmeligio/flutter-docker-image` and confirm the configured `pages` outline appears
- [ ] 4.3 Spot-check that pages distinguish android image vs windows image content
