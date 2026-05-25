## 1. Replace SHA pin with release-identity check in `update_windows_version`

- [x] 1.1 Collapse the existing "Resolve VS catalog manifest payload" + "Download and verify VS catalog manifest" steps in `.github/workflows/update_version.yml` into a single step that fetches `vsman.json` from `channel.json.channelItems[…].payloads[0].url` without computing or comparing a SHA-256.
- [x] 1.2 Add a new step "Verify channel and vsman describe the same release" that extracts `channel.json.info.productSemanticVersion` and `vsman.json.info.productSemanticVersion` via `jq` and compares them; on mismatch, log a `::warning::` naming both values and proceed to step 1.3's skip branch.
- [x] 1.3 Wrap the existing "Resolve VS BuildTools component versions" → "Write windows block into config/version.json" → "Validate version.json with CUE" → "Stage windows-only artifact" → "Upload artifact with the updated windows block" steps with `if: steps.<release-identity-step>.outputs.matched == 'true'` so they only run when the check passes.
- [x] 1.4 Add a `windows_skipped` job output to `update_windows_version`, set to `'true'` when the release-identity check fails and `'false'` otherwise. Default the `version_artifact_id` output to empty string when skipped.
- [x] 1.5 Remove the now-unused `vsman_payload.outputs.sha` plumbing.

## 2. Make `vs-manifests` forensic upload unconditional

- [x] 2.1 In `.github/workflows/update_version.yml`, change the "Upload VS manifest artifacts for forensics" step to use `if: always()` so it runs whether the release-identity check passed or failed.
- [x] 2.2 Verify the artifact upload step references both `channel.json` and `vsman.json` paths and that both files exist on disk by the time the step runs (they will, since both are fetched before the check).

## 3. Decouple `update_docs_and_create_pr` from `update_windows_version` failure

- [ ] 3.1 Update the "Download configuration artifacts" step in `update_docs_and_create_pr` to make the windows artifact id optional: when `needs.update_windows_version.outputs.version_artifact_id` is empty, omit it from the `artifact-ids` input.
- [ ] 3.2 Wrap the "Merge windows block into version.json" step with a condition that runs the merge only when the windows artifact was downloaded; otherwise leave `config/version.json` as produced by the Android artifact (whose `windows` block came from the base branch checkout).
- [ ] 3.3 Add a step that composes an additional line for the PR body when `needs.update_windows_version.outputs.windows_skipped == 'true'`, with text like "Windows toolchain unchanged this cycle — see windows job log: <url>" and a `${{ … }}` expression that interpolates the job's run URL.
- [ ] 3.4 Ensure `update_docs_and_create_pr` continues to require `update_windows_version` in `needs:` (to preserve sequencing) but does not gate on its conclusion — the step-level conditions in 3.1–3.3 handle the skip case.

## 4. Local validation against today's broken upstream

- [ ] 4.1 Run `openspec validate p11-resilient-windows-update --strict` and confirm no errors.
- [ ] 4.2 Verify the workflow YAML parses without errors via `act --dryrun -W .github/workflows/update_version.yml` or equivalent (or by inspection if `act` is not available).
- [ ] 4.3 In the implementation PR description, document the manual verification plan: trigger `update_version.yml` via `workflow_dispatch` on the PR branch after merge to main; confirm (a) `update_windows_version` ends with `windows_skipped=true` against Microsoft's currently-inconsistent upstream, (b) `update_docs_and_create_pr` produces a PR with unchanged `windows` block, (c) the `vs-manifests` artifact is present.

## 5. Archive cleanup

- [ ] 5.1 Add a short note in `p3-windows-version-schema`'s archived design (or a forward-pointer in this change's design.md, whichever is acceptable to the archive convention) flagging that the "free integrity property" decision was superseded by `p11-resilient-windows-update`. Reference: design.md "Decision: Replace byte-level SHA check with semantic release-identity check".
