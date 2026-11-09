# Tasks

## 1. Comment script

- [ ] 1.1 Write `script/commentScoutReport.ts` (CommonJS, erasable TS only): build marker from `IMAGE`, truncate `REPORT` with run link, paginate `issues.listComments`, update the `github-actions[bot]` comment whose body starts with the marker or create one; verify `node -e "require('./script/commentScoutReport.ts')"` loads it under Node 24.22.2 without errors

## 2. Workflow wiring

- [ ] 2.1 In `build.yml` `scan-image`, add a sparse checkout of `script/` using the repo's pinned `actions/checkout` SHA; verify the workflow lints via gx
- [ ] 2.2 Set `write-comment: false` on the `Scan with Docker Scout` step, leaving other inputs unchanged; verify by diff
- [ ] 2.3 Add `Comment Scout report on PR` step: pinned `actions/github-script` v8.0.0 SHA, `if: github.event_name == 'pull_request' && steps.docker-scout.outputs.compare != ''`, `env` `IMAGE`/`REPORT`, script `require('./script/commentScoutReport.ts')`; verify the workflow lints via gx

## 3. Integration check

- [ ] 3.1 Open the PR and verify the run posts one comment per image with marker `<!-- scout-compare:<image> -->`
- [ ] 3.2 Push a second commit and verify the same three comments are updated in place, not duplicated
- [ ] 3.3 Verify each leg's job summary still shows the full Scout report

## Workflow follow-up

- Archive the change and sync `ci-image-vulnerability-scan` after merge.
- Close #560.
