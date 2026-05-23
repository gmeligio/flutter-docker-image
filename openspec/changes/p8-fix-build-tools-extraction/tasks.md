## 1. Fix the build-tools extractor

- [ ] 1.1 In `.github/workflows/update_version.yml`, update the `Update Android SDK build tools version` step (around line 244) to anchor the grep at start-of-line (`grep '^build-tools'`) and add `,` to the awk field separator (`awk -F'[;,:]' '{print $2}'`).
- [ ] 1.2 Verify locally by running the same pipeline against `https://raw.githubusercontent.com/flutter/flutter/refs/tags/3.41.9/engine/src/flutter/tools/android_sdk/packages.txt` and confirming the extracted value is exactly `36.1.0` (no trailing characters).

## 2. Add producer-side validation in `update_android_version`

- [ ] 2.1 Add a new step `Validate version.json with CUE` immediately before the `Upload artifact with the updated version.json` step in the `update_android_version` job. Use `run: cue vet config/schema.cue -d '#Version' config/version.json`.
- [ ] 2.2 Confirm `mise` (which provides `cue`) is already set up earlier in the same job — it is via the existing `Setup mise tools` step at line 273. No additional setup needed.

## 3. Validate the workflow

- [ ] 3.1 Run `openspec verify --change p8-fix-build-tools-extraction` and resolve any findings.
- [ ] 3.2 Open a PR with the workflow change.
- [ ] 3.3 Trigger `update_version.yml` via `workflow_dispatch` on the PR branch and confirm `update_android_version`, `validate_config_version`, and `update_docs_and_create_pr` all complete successfully against the current Flutter tag.
- [ ] 3.4 Confirm the generated `config/version.json` in the resulting PR contains `android.buildTools.version == "36.1.0"`.
