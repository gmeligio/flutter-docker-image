# Tasks

## 1. Comment script

- [x] 1.1 Write `script/commentScoutReport.ts` (CommonJS, erasable TS only): build marker and `### Docker Scout compare: <image>` heading from `IMAGE`; read `REPORT_FILE`, warn and return if missing or empty; truncate with run link; paginate `issues.listComments`, update the oldest `github-actions[bot]` comment whose body starts with the marker and delete other matches, or create one; catch API errors as `core.warning` naming the image; verify it loads with `node -e "require('./script/commentScoutReport.ts')"` on Node 24.22.2
- [x] 1.2 Run the script locally through the pinned github-script `dist/index.js` on Node 24.22.2 with stubbed `github`/`core` and verify: (a) no match → create called, (b) two matches → update called on the oldest id, delete on the other, (f) a bot comment without the marker and a non-bot comment starting with the marker → neither updated nor deleted, create called, (c) a 200 KiB report file → body length ≤ 65,536, starts with marker, ends with the truncation note and run link, (d) missing and empty file → warning naming the image, no API call, (e) API throws → warning text contains the image and the error message, exit 0

## 2. Workflow wiring

- [x] 2.1 In `build.yml` `scan-image`, add `contents: read` to the job `permissions:` and a sparse checkout of `script/` placed before the logins and the Scout step, using the repo's pinned `actions/checkout` SHA; verify the workflow lints via gx
- [x] 2.2 On the `Scan with Docker Scout` step (keeps `id: docker-scout`, which the comment step's gate reads) keep `write-comment: false` and remove `format`/`output`; add a `Save Scout report` `run:` step after it, `if: ${{ !cancelled() && steps.docker-scout.outcome != 'skipped' }}`, writing `${{ steps.docker-scout.outputs.compare }}` to `$RUNNER_TEMP/scout-compare.md` through a `<<'SCOUT_REPORT_EOF'` heredoc; verify the workflow lints via gx and a local `bash` run of the same heredoc with a report containing `$HOME`, backticks and quotes writes it byte-for-byte
- [x] 2.3 Add `Comment Scout report on PR` step: pinned `actions/github-script` v8.0.0 SHA, `if: ${{ !cancelled() && github.event_name == 'pull_request' && steps.docker-scout.outcome != 'skipped' }}`, `env` `IMAGE` and `REPORT_FILE: ${{ runner.temp }}/scout-compare.md`, script wrapping `require('./script/commentScoutReport.ts')` and its call in `try/catch` → `core.warning` naming the image; verify the workflow lints via gx

## 3. Integration check

- [x] 3.1 Open the PR and verify the run posts one comment per `scout: true` image with marker `<!-- scout-compare:<image> -->` and a visible image heading; if the `compare` step output is empty, stop and revise the design before continuing
- [ ] 3.2 Push a second commit and verify the same comments are updated in place, one per image, none duplicated
- [ ] 3.3 Re-run only the flutter-web leg and verify only the flutter-web comment's `updated_at` changes
- [ ] 3.4 Verify each leg's job summary still shows the full Scout report, and the Scout step log still shows `compare` executing and the SBOM attestation being used
- [x] 3.5 Verify the gate by inspection: the comment step's `if:` is false for `workflow_dispatch` and when the Scout step was skipped (no baseline)

## Workflow follow-up

- Archive the change and sync `ci-image-vulnerability-scan` and `ci-parallel-image-validation` after merge.
- Close #560.
