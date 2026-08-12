One PR plus a one-off sweep. No dependencies on other changes. Line citations
are against `ae870a0`.

## 1. Clean every image that produces handoff tags

- [x] 1.1 Confirm which images produce handoff tags before writing the matrix: `build.yml:48-55` matrixes `flutter-android` and `flutter-web`, and the GHCR ref comes from `matrix.name` (`:64`, `:132-138`). `windows.yml:19-22` calls `windows-image.yml` with `push: false`, so `flutter-windows` pushes nothing on a PR
- [x] 1.2 Replace the hardcoded `PACKAGE_NAME: flutter-android` (`cleanup-pr-image.yml:26`) with a matrix over those images, keeping `PACKAGE_NAME` as the per-leg env var so the API calls at `:66` and `:82` are untouched
- [x] 1.3 Set `fail-fast: false` on that matrix, so one image's cleanup failure does not skip another's
- [x] 1.4 Confirm a leg with nothing to delete still exits cleanly — the existing "tag not found" path (`:71-73`) and the 404-idempotency case (`:88-90`) already cover it
- [x] 1.5 Confirm the tag-regex guard (`:49-52`) is unchanged and still refuses anything that is not `pr-<N>` or `branch-<ref>`, so release tags and `buildcache` stay unreachable

## 2. Sweep the existing orphans

- [ ] 2.1 Re-count handoff tags on **both** packages immediately before the sweep — as of 2026-08-12, 33 on `flutter-web` (32 orphans, `pr-489` … `pr-543`) and 4 on `flutter-android` (3 orphans, `pr-454/455/456`), with `pr-533` the only open PR. Both will have moved. Work from the fresh list, not the recorded one
- [ ] 2.2 Sweep `flutter-android` too: it carried 3 orphans (`pr-454`, `pr-455`, `pr-456`) despite being the image the workflow already names, so the matrix fix alone does not clear them. Leaving them would make 2.8's check meaningless
- [ ] 2.3 Expect no `branch-<ref>` tags on either package — there were none as of 2026-08-12. If any appear, sweep them under the same guard, except `branch-main`, which is left in place (see 5.5). Do not assume the list is `pr-` only
- [ ] 2.4 Build the open-PR exclusion list from `gh api "/repos/gmeligio/flutter-docker-image/pulls?state=open" --jq '[.[].number]'`, and re-check it immediately before issuing any DELETE — not only at 2.1. A PR opened mid-sweep would otherwise have its handoff tag deleted under a running build, breaking `test-image`'s pull (`build.yml:258`) and `scan-image`'s digest resolve (`:322`)
- [ ] 2.5 Apply the same regex guard the workflow uses (`^pr-[0-9]+$`, `^branch-[A-Za-z0-9._-]+$`) to every tag on the sweep list before deleting anything, since the one-off runs outside the workflow that enforces it
- [ ] 2.6 Delete by resolving each `pr-<N>` tag to a version ID and deleting that ID — **never** a `tags == []` filter, which matches OCI index children and would break parent tags
- [ ] 2.7 Dry-run first: print the resolved (tag, version_id) pairs and confirm the list against 2.1 before any DELETE is issued
- [ ] 2.8 Re-count **handoff** tags on both packages afterwards; expect only open-PR tags to remain. Total tag counts stay high and that is correct: `flutter-android` should still carry ~157 tags, including 59 legacy `<semver>-<sha>` and bare-`<sha>` tags that are out of scope (see 5.4). A low total means the sweep over-deleted, not that it worked

## 3. De-scope the spec

- [x] 3.1 Drop the `ghcr.io/<owner>/flutter-android` scoping from the capability Purpose (`openspec/specs/ci-image-tag-lifecycle/spec.md:5`) **in this PR**, not on archive. OpenSpec 1.3.1's delta parser recognises only ADDED/MODIFIED/REMOVED/RENAMED *Requirements* (`core/parsers/change-parser.js:67-117`); `specs-apply.js` rebuilds a spec from those and preserves the existing Purpose verbatim, so no delta can carry this. Editing it directly is safe for the same reason — archive will not overwrite it
- [x] 3.2 Confirm the two requirements left unmodified — *Cleanup never targets a non-handoff tag* (`:47`) and *Cleanup workflow runs with minimum privilege* (`:68`) — still read correctly for a multi-image workflow, and that `permissions:` needs no change for the added legs

## 4. Verification

- [ ] 4.1 Close a PR after the change lands and confirm neither image retains its `pr-<N>` tag
- [ ] 4.2 Confirm the run shows exactly two legs (`flutter-android`, `flutter-web`), and that a leg with nothing to delete is green rather than red — asserting the count catches a future image that silently fails to appear
- [ ] 4.3 Confirm the sweep and the workflow touched nothing outside the handoff-tag regex. Check every non-handoff category, not just releases and `buildcache`: `flutter-android`'s 59 legacy `<semver>-<sha>` and bare-`<sha>` tags must also be intact. Diff the full tag list against the pre-sweep capture from 2.1 — the deleted set should be exactly the orphan list and nothing else

## 5. Wrap-up

- [ ] 5.1 Open the PR with a Conventional Commit title, one logical concern. The group-2 sweep is not part of the PR — it is a manual registry operation with no diff, tracked here and recorded in the PR body
- [ ] 5.2 Note in the PR the orphan count swept and that deletion resolved version IDs rather than filtering on empty tags
- [ ] 5.3 File an issue for the same defect one capability upstream: `ci-image-handoff/spec.md:13,15,26,27` hardcodes `flutter-android` in the outputs that *produce* the tags this change deletes, while `web-image-testing/spec.md:52` already asserts `ghcr.io/<owner>/flutter-web:pr-<N>` exists. The two main specs contradict each other today, independent of this change. Out of scope here — fixing it would break the one-logical-concern rule
- [ ] 5.4 File an issue for `flutter-android`'s 59 legacy tags — 28 `<semver>-<sha>`, 31 bare `<sha>`, all 3.7.x–3.10.x, produced by no current workflow. Whether they should be retired is a real question (they may be pinned by old docs or downstream users) and is not this change's concern; recording them stops the next audit from rediscovering them cold
- [ ] 5.5 If a `branch-main` tag turns up during the sweep, leave it. Cleanup cannot reach it — `main` is never deleted, so the `delete` event never fires — but it is one mutable tag that each dispatch overwrites, not an accumulating orphan, and it holds the latest `main` build. Nothing to fix; noted so a future sweep does not rediscover it as a leak
