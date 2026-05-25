## Why

The `update_windows_version` job in `.github/workflows/update_version.yml` hard-fails when the byte-level SHA-256 of `VisualStudio.vsman` doesn't match the value pinned in `channel.json` — and because `update_docs_and_create_pr` lists `update_windows_version` in `needs:`, that failure cascades into a *skipped* PR-creation job, blocking the entire monthly upgrade PR. Since 2026-05-19 every scheduled run of `update_version.yml` has failed for this reason, producing zero upgrade PRs over a 7-day window.

Investigation showed the byte-level pin is incompatible with how Microsoft actually serves the manifest: `channel.json` is generated against a pretty-printed (~30 MB) vsman and pins its SHA, while the CDN serves a minified (~18 MB) version of the same content. The two byte streams describe the *same* release — every identifier (`buildVersion`, `productSemanticVersion`, `productPatchVersion`) matches across both files — they just differ in JSON formatting. The integrity check the workflow needs is **semantic** ("channel and vsman describe the same release") not **byte-level** ("the bytes I downloaded hash to the value pinned upstream"). This change replaces the brittle byte-pin with a release-identity check, makes the Windows job non-blocking for PR creation (so Flutter+Android updates land even when Microsoft's manifest is mid-publish), and always preserves the forensic manifests as artifacts.

## What Changes

- **BREAKING (workflow):** Replace the `sha256sum -c` verification step in `update_windows_version` with a release-identity check that compares `channel.json.info.productSemanticVersion` against `vsman.json.info.productSemanticVersion`. Mismatch is treated as a soft failure for the Windows job — the job records the skip and exits without producing an artifact, but does not fail the workflow.
- Drop the now-unused `vsman_payload.outputs.sha` step output and rename the surrounding steps to reflect that channel.json is a *discovery* document, not a hash oracle.
- Make `update_docs_and_create_pr` resilient to a missing `update_windows_version` artifact: when the Windows artifact is absent, the PR is composed from the existing committed `windows` block in `config/version.json` (unchanged byte-for-byte) plus the fresh Flutter and Android blocks. The PR body annotates "Windows toolchain unchanged this cycle" with a link to the Windows job log.
- Make the `vs-manifests` forensic artifact upload (`channel.json` + `vsman.json`) run unconditionally (`if: always()`) so the bytes that triggered a release-identity mismatch are preserved for retroactive inspection, including signature verification by hand if ever needed.
- Document in `windows-version-tracking` design history that VS uses two parallel version notations (`buildVersion` 17.14.37314.3 ↔ `productSemanticVersion` 17.14.33+37314.3) for the same release, to prevent future "version mismatch" misreadings.

## Capabilities

### New Capabilities

(none — this change refines existing behavior, it doesn't introduce a new capability)

### Modified Capabilities

- `windows-version-tracking`: the requirement "Monthly upgrade PR includes Windows toolchain updates" is extended with a new scenario covering the case where the upstream VS manifest is mid-publish (channel.json and vsman.json disagree on release identity); in that case the upgrade PR still opens with Flutter and Android updates while the `windows` block is carried forward unchanged. The integrity check used to gate the Windows update changes from byte-level SHA-256 of vsman against `channel.payloads[0].sha256` to semantic agreement of `info.productSemanticVersion` between the two files.
- `flutter-version-update`: the requirement "Upgrade PR contains a coherent, validated `version.json`" is extended so the PR opens even when the Windows update produced no artifact this cycle — the existing committed `windows` block satisfies CUE validation and is carried forward unchanged.

## Impact

- Affected files: `.github/workflows/update_version.yml` (verification step rewrite + `update_docs_and_create_pr` artifact-handling change + unconditional forensic upload).
- No code changes in `windows.Dockerfile`, `script/setEnvironmentVariables.js`, `config/schema.cue`, or `config/version.json` — the data contract is unchanged.
- No new external dependencies. Drops one implicit dependency (byte-fidelity from Microsoft's CDN) that was unenforceable upstream.
- Risk: a forged vsman that copies the legitimate `productSemanticVersion` field but contains wrong component versions would pass the release-identity check. Mitigation: the existing Pester suite on `windows-2025` re-asserts manifest-vs-image versions at build time — a forged version that doesn't actually install fails the image build before PR merge. This is the same load-bearing safety net the byte-SHA check ultimately depended on.
- Relevance gate: this change passes — it modifies an existing capability's behavior (the integrity-check mechanism and the failure-propagation model), not just a private implementation detail. A CI engineer reading the spec needs to know that `update_windows_version` failure no longer blocks PR creation, and that the integrity guarantee is semantic, not byte-level.
