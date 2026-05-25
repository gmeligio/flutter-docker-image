## Context

`update_windows_version` was added in `p3-windows-version-schema` to fetch VS BuildTools component versions monthly from Microsoft's VS catalog manifest. The design banked on `channel.json` SHA-256-pinning `vsman.json` as a "free integrity property" — the workflow downloads vsman, hashes it, compares against `channel.json.channelItems[…].payloads[0].sha256`, fails the job on mismatch.

That assumption broke. Reproduced locally on 2026-05-25:

| | `channel.json` advertises | Served bytes |
|---|---|---|
| sha256 | `9393558b…61a4` | `f7eb8ea0…6438` |
| size | 30,439,301 bytes | 17,952,555 bytes |

But every release-identifying field in both files matches: `buildVersion: 17.14.37314.3`, `productSemanticVersion: 17.14.33+37314.3.-may.2026-`, `productPatchVersion: 33`. The two files describe the same release, in different JSON serializations. Microsoft's release tooling generates a pretty-printed (~30 MB) vsman, computes its SHA, pins that in channel.json — and then serves a minified (~18 MB) version of the same content from the CDN. The byte-level check is structurally incompatible with how the data is delivered.

There are two parallel version notations in VS releases, easy to misread as different releases:

- `buildVersion` — build pipeline identifier, `major.minor.build.revision` (e.g., `17.14.37314.3`)
- `productSemanticVersion` — marketing/semver identifier, includes `productPatchVersion` and a `+buildVersion.suffix` (e.g., `17.14.33+37314.3.-may.2026-`)

Both notations identify the same artifact. Initial research into this failure misread the two as inconsistent before catching that they're aliases.

The workflow today also couples the PR-creation job to the Windows job via `update_docs_and_create_pr.needs: [update_windows_version, …]`. When the Windows job fails, GitHub Actions marks the dependent job *skipped* — silently producing no PR for that cycle. Seven consecutive scheduled runs have produced zero upgrade PRs since the upstream breakage on 2026-05-19.

## Goals / Non-Goals

**Goals:**

- Replace the brittle byte-level SHA check with a semantic check that matches Microsoft's actual delivery pattern.
- Decouple PR creation from Windows-job success: Flutter and Android updates ship even when Microsoft's VS manifest is mid-publish or inconsistent.
- Preserve a forensic record (channel.json + vsman.json bytes) every run, including when the release-identity check fails — so future investigation has the bytes to inspect.
- Document the two-notation insight in design history so future maintainers don't repeat the misreading.

**Non-Goals:**

- Cryptographic signature verification of `vsman.json`. The file carries an embedded `signature` + X.509 chain to Microsoft Root CA 2011, and signature verification is the strongest available integrity check, but it requires reverse-engineering Microsoft's undocumented JSON canonicalization (`signature.signInfo.canonicalization` is blank in the published manifest). There is no off-the-shelf Linux tool. The release-identity check catches every failure mode we've ever observed at near-zero cost; cryptographic verification is deferred until a concrete threat justifies the engineering investment, or until the job moves to a Windows runner where VS Setup's verification machinery is built in.
- Mirroring or pre-fetching Microsoft's manifests to a stable location we control. The two-step `aka.ms` → `download.visualstudio.microsoft.com` flow is fine; only the integrity check needed adjustment.
- Splitting the upgrade PR into one-per-platform. Solo maintainer favors fewer reviews; the per-platform failure isolation we need is achievable inside the single-PR design by letting the PR job proceed without the Windows artifact.

## Decisions

### Decision: Replace byte-level SHA check with semantic release-identity check

Compare `channel.json.info.productSemanticVersion` against `vsman.json.info.productSemanticVersion`. Both files publish this field; both currently agree (`17.14.33+37314.3.-may.2026-` today). When they disagree, Microsoft's release pipeline is mid-publish or inconsistent, and we should not trust the data extracted from vsman.

Alternatives considered:

- **Keep the SHA check, write our own JSON canonicalization to neutralize the pretty-vs-minified difference.** Rejected: Microsoft doesn't document their canonical form; we'd be reverse-engineering it. Likely fragile and definitely high-maintenance.
- **Verify the embedded vsman signature.** Rejected for now: same canonicalization problem (signature is computed over a canonical content form), plus X.509 chain validation glue. Real engineering cost for a threat model we don't have evidence for. Re-evaluate if the job ever moves to a Windows runner.
- **Compare `buildVersion` instead of `productSemanticVersion`.** Both work today; `productSemanticVersion` is preferred because it includes both the marketing version (`17.14.33`) and the build identifier (`37314.3`) — a single field that detects drift in either dimension. `buildVersion` alone misses changes to `productPatchVersion`; `productSemanticVersion` does not.

### Decision: `update_windows_version` failure does not block PR creation

`update_docs_and_create_pr` keeps `update_windows_version` in `needs:` (so it waits for it to finish), but the artifact-handling steps tolerate the Windows artifact being absent. When the release-identity check fails, the Windows job exits successfully (zero status) without uploading a `version.json.windows` artifact and emits a `windows_skipped=true` job output. The PR-creation job reads this output and either merges the Windows artifact (success path) or carries forward the existing committed `windows` block (skip path).

This matches the existing requirement in `windows-version-tracking` spec scenario "No Windows update needed in this cycle": the PR still opens, the `windows` block is unchanged.

Alternatives considered:

- **Hard `if: success()` on Windows job, hard-fail the PR job otherwise.** Today's behavior. Rejected: the failure-propagation model treats every Windows-side hiccup as catastrophic, which contradicts the spec's stated intent that the manifest read is a "suggestion not a truth" (`p3-windows-version-schema/design.md:34`).
- **Remove `update_windows_version` from `needs:` entirely.** Rejected: this would let the PR job race the Windows job. Keeping the `needs:` edge but tolerating a missing artifact is the cleanest model — sequencing is preserved, output is opportunistic.

### Decision: Forensic artifact upload is unconditional

The `vs-manifests` artifact (channel.json + vsman.json) currently uploads only on the success path of the Windows job. Move it to run on `if: always()` — when the check fails, we want the bytes preserved more than ever, because they're the evidence of upstream inconsistency. 90-day artifact retention is the audit trail.

This also means a future operator wanting to verify the vsman signature by hand (using PowerShell on a Windows machine, or `vswhere` introspection) has the bytes available without re-deriving them from Microsoft's now-rolled-forward CDN.

### Decision: Document the two-notation insight in spec history

`buildVersion` vs `productSemanticVersion` is the kind of detail that gets re-discovered painfully every few years. Add a short note in `windows-version-tracking` spec's design rationale (carried via this change's design.md, archived alongside) that calls out the two notations and which fields are aliases. Future updates to the integrity check don't need this rediscovered.

## Risks / Trade-offs

- **[Risk] A forged or substituted vsman that copies the legitimate `productSemanticVersion` would pass the release-identity check.** → Mitigation: the Pester suite on `windows-2025` asserts that the manifest-pinned VS component versions actually install on the image. A forged version that isn't a real downloadable component fails `docker build` before any PR merges. This is the same load-bearing semantic check the byte-SHA pin ultimately depended on.

- **[Risk] Microsoft publishes a vsman with a stale `productSemanticVersion` that matches channel.json but contains old component versions.** → Mitigation: monotonicity is enforced downstream — the Pester suite compares manifest-claimed versions to actually-installed versions on every PR. A regression would surface as a test failure on `windows-2025`, not a silent merge.

- **[Risk] Drift between `productSemanticVersion` and `buildVersion` in some future Microsoft schema change could leave us checking the wrong field.** → Mitigation: the check is one `jq` expression; if Microsoft ever drops `productSemanticVersion`, the check fails loudly (field returns `null`, mismatch), the Windows job skips, an operator investigates. Same failure mode as a real release-identity mismatch.

- **[Trade-off] We give up byte-level tamper detection.** → Acceptable: HTTPS to `*.visualstudio.microsoft.com` provides wire integrity, the vsman's embedded signature is preserved in the forensic artifact for retroactive inspection if needed, and the Pester suite catches any extracted-version that doesn't correspond to a real installable component. The threat we lose visibility on (a Microsoft CDN serving Microsoft-signed bytes that nonetheless got tampered with between publication and our download) has no real-world precedent for this workload.

- **[Trade-off] The PR may land with a stale `windows` block when the upstream channel/vsman pair is inconsistent for an extended period.** → Acceptable: pinning is the point. A stale `windows` block is *correct*, just not *current*. The next cycle re-tries the fetch; when Microsoft's pipeline self-heals, the next PR bumps the block forward.

## Automated Test Strategy

- **No new test infrastructure.** The change is in `update_version.yml` only. Verification happens at three existing layers:
  - **Workflow-level**: `validate_config_version` job continues to `cue vet` the merged `config/version.json` after the PR job composes it. If the Windows-skip path leaves an invalid manifest (it shouldn't, since carrying forward an already-valid block is a no-op), this catches it.
  - **Image-build level**: `windows.yml` rebuilds the image on `windows-2025` against whatever `config/version.json` contains. A regression in the manifest fails `docker build`.
  - **Image-test level**: the Pester suite (`test/windows/Windows.Tests.ps1`) asserts the installed component versions match the manifest. A forged-but-shape-correct manifest fails here.
- **Manual verification step during rollout**: trigger `update_version.yml` via `workflow_dispatch` after the change merges, confirm that (a) the Windows job emits `windows_skipped=true` (since Microsoft's upstream is still mismatched), (b) the PR opens with Flutter+Android updates and an unchanged `windows` block, (c) the `vs-manifests` artifact is uploaded.

## Observability

- **Release-identity mismatch logs to job output**: when `channel.info.productSemanticVersion != vsman.info.productSemanticVersion`, the step logs `::warning::release identity mismatch: channel=X vsman=Y — skipping Windows update this cycle` (GitHub Actions surfaces `::warning::` markers in the run summary).
- **Job output `windows_skipped` is visible in the run graph**: `update_docs_and_create_pr` reads this output, and the run summary will show `windows_skipped=true` against the Windows job, making it obvious from the dashboard view why the PR's `windows` block is unchanged.
- **PR body annotation**: `update_docs_and_create_pr` adds a one-line note to the PR description ("Windows toolchain unchanged this cycle — see windows job log: <url>") when the Windows artifact was absent. The reviewer sees the reason without having to dig.
- **Forensic artifact always present**: `vs-manifests` is uploaded on every run, so post-hoc "why did this PR not bump Windows" investigation has the channel.json and vsman.json that the workflow saw.
- **No silent failures**: every code path either uploads the Windows artifact (success) or logs a `::warning::` + sets `windows_skipped` (skip). The PR job never opens a PR without acknowledging which path the Windows job took.

## Migration Plan

- This is a workflow change with no schema, manifest, or image impact. Land as a single PR.
- After merge, the next scheduled run (or a `workflow_dispatch`) exercises the new path against Microsoft's currently-broken upstream — which is fortunate, because it validates the skip path end-to-end without any contrived test setup.
- Rollback: revert the PR. The previous behavior (hard SHA check, PR-blocked-by-Windows) returns. No data migration, no state change.

## Open Questions

- None blocking. The cryptographic signature path is documented as a future option; the release-identity check is the load-bearing decision and has been validated against the actual failure mode.
