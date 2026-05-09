## 1. Pre-flight

- [x] 1.1 Run `gx tidy` against the current tree and confirm zero diff (proves the manifest, lock, and workflows are mutually consistent before changing Renovate)
- [x] 1.2 Confirm Mend Renovate App is the bot in use by checking the author of the most recent Renovate PR

## 2. Rewrite `.github/renovate.json`

- [x] 2.1 Add a `packageRules` entry that disables Renovate's built-in `github-actions` manager (`matchManagers: ["github-actions"]` + `enabled: false`)
- [x] 2.2 Remove the existing `github-actions` package rule (the one with `matchDatasources: ["github-tags"]` and the monthly schedule)
- [x] 2.3 Add a `customManagers` regex entry targeting `^\\.github/gx\\.toml$` with named captures `depName`, `packageName`, `currentValue`, datasource `github-tags`, versioning `npm`, and `extractVersionTemplate: "^v?(?<version>.+)$"`
- [x] 2.4 Add a new `packageRules` entry keyed on `matchFileNames: [".github/gx.toml"]` with `groupName: "github-actions"` and the existing monthly schedule `["* 0-3 1 * *"]`
- [x] 2.5 Preserve the existing Dockerfile `customManagers` entry untouched
- [x] 2.6 Preserve the existing `extends` array untouched

## 3. Local validation

- [x] 3.1 Run `npx --package renovate -- renovate-config-validator .github/renovate.json` and confirm exit 0
- [x] 3.2 Run `renovate --platform=local --dry-run=full` (with `LOG_LEVEL=debug`) and confirm: (a) zero upgrades from the `github-actions` manager, (b) `actions/checkout` is extracted with `packageName=actions/checkout` and a current version, (c) `github/codeql-action/upload-sarif` is extracted with `packageName=github/codeql-action`, (d) `plexsystems/container-structure-test-action` is extracted with the `~0.3.0` specifier
- [x] 3.3 If validation fails on the two-named-capture regex, fall back to a `packageNameTemplate` Handlebars conditional that returns the first two slash-separated segments of `depName`, and re-run 3.1 and 3.2

## 4. Open the PR

- [ ] 4.1 Commit the `renovate.json` change on a topic branch and open a PR
- [ ] 4.2 Confirm `gx.yml` `lint` and `tidy` jobs pass on the PR (no functional change yet, so they should be green)
- [ ] 4.3 Merge after review

## 5. Post-merge observation (next Renovate cycle)

- [ ] 5.1 On the next monthly Renovate cycle, confirm any opened upgrade PR edits only `.github/gx.toml`
- [ ] 5.2 Confirm `gx.yml`'s `tidy` job pushes a follow-up commit on the PR branch with `gx.lock` and workflow updates
- [ ] 5.3 Confirm `gx lint` passes on the head commit of the Renovate PR
- [ ] 5.4 If no Renovate PR appears within the expected window, check the Mend dashboard for manager-extraction errors against `gx.toml` and resolve before archiving

## 6. Archive

- [ ] 6.1 Run `/opsx:verify` to validate that the shipped behavior matches the specs
- [ ] 6.2 Run `/opsx:archive` to fold the spec delta into `openspec/specs/actions-version-tracking/spec.md`
