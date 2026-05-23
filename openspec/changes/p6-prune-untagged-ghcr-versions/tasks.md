## 1. Add the pruning workflow

- [ ] 1.1 Create `.github/workflows/prune_ghcr_untagged.yml` with:
  - `on.schedule: [{ cron: '0 4 * * 0' }]` (Sundays 04:00 UTC).
  - `on.workflow_dispatch.inputs.dry_run: { type: boolean, default: true }`.
  - `permissions: { packages: write, contents: read }`.
  - `concurrency: { group: prune-ghcr-untagged, cancel-in-progress: false }`.
- [ ] 1.2 Resolve effective `dry_run` for the run:
  - `schedule` event → `dry_run=false`.
  - `workflow_dispatch` event → use the input (default true).
- [ ] 1.3 Compute the cutoff timestamp from `RETENTION_DAYS` (env, default `7`): `CUTOFF=$(($(date -u +%s) - RETENTION_DAYS * 86400))`.
- [ ] 1.4 Capture `tagged_count_before` by listing all versions where `metadata.container.tags != []`.
- [ ] 1.5 Enumerate candidates: `gh api /user/packages/container/flutter-android/versions --paginate --jq ".[] | select(.metadata.container.tags == [] and (.created_at | fromdateiso8601) < $CUTOFF) | .id"`.
- [ ] 1.6 For each candidate id, log `INFO: deleting <id> created=<iso> tags=[] sha=<digest>`. When `dry_run=false`, issue `gh api -X DELETE /user/packages/container/flutter-android/versions/<id>` and treat HTTP 404 as success (log and continue).
- [ ] 1.7 After the loop, capture `tagged_count_after` and `untagged_count_after`. Assert `tagged_count_after == tagged_count_before` — on mismatch, emit `::error::tagged_count changed: before=$before after=$after` and exit 1.
- [ ] 1.8 Print summary: `INFO: pruned N versions (dry_run=<bool>), M untagged remain, K tagged kept`.

## 2. Validate on the live registry

- [ ] 2.1 Trigger `workflow_dispatch` with `dry_run: true`. Expect: candidate count > 800 (matches the 836 measured 2026-05-23 minus any deleted by p4 in the interim); zero DELETE calls in the log; `tagged_count_before == tagged_count_after` trivially holds.
- [ ] 2.2 Spot-check 3 candidate ids from the log against `gh api /user/packages/container/flutter-android/versions/<id>`. Confirm each has `metadata.container.tags == []` and `created_at` older than 7 days.
- [ ] 2.3 Trigger `workflow_dispatch` with `dry_run: false`. Expect: ~ same N deletions as the dry-run count; tagged-count invariant holds; final summary line names the new totals.
- [ ] 2.4 Verify the protected set: `gh api /user/packages/container/flutter-android/versions --paginate --jq '[.[] | select(.metadata.container.tags != [])] | length'` returns the same number as before the run.
- [ ] 2.5 Verify specific tags survived: `gh api /user/packages/container/flutter-android/versions --paginate --jq '.[] | select(.metadata.container.tags[]? == "buildcache" or .metadata.container.tags[]? == "3.41.9")'` returns non-empty for each.

## 3. Verify idempotence and edge cases

- [ ] 3.1 Re-run `workflow_dispatch` with `dry_run: false` immediately after step 2.3. Expect: 0 candidates (or only versions that became eligible in the last few seconds), workflow exits 0, summary line shows "pruned 0".
- [ ] 3.2 Manually delete one candidate id between enumeration and the workflow's DELETE call (simulate race): create a feature branch, push a deliberate sleep into the workflow between enumeration and the DELETE loop, then race a manual `gh api -X DELETE` against it. Confirm the workflow logs the 404 and continues. Revert the sleep.
- [ ] 3.3 Confirm the recent-orphan preservation: count untagged versions with `created_at` in the last 7 days before the run, run, count again. They should be unchanged.

## 4. Wait one schedule cycle

- [ ] 4.1 After the first natural Sunday-04:00 cron firing, inspect the run log. Confirm: schedule event → `dry_run=false` was applied, deletions occurred, tagged-count invariant held, summary line is sensible.
- [ ] 4.2 Add a one-line note in `docs/contributing.md` (or equivalent) describing the weekly prune, in case a maintainer sees a version disappear and wants to understand why.
