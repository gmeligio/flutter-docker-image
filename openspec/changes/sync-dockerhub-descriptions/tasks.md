## 1. Release CI (release.yml)

- [ ] 1.1 Add `flutter-windows` as a third entry to the `update-description` matrix
- [ ] 1.2 Add a `short:` field to each matrix entry with its per-platform value:
  - `flutter-android`: `Flutter with Android SDK & Fastlane for CI`
  - `flutter-web`: `Flutter with precached web engine for CI`
  - `flutter-windows`: `Flutter with VS Build Tools for CI`
- [ ] 1.3 Change `short-description:` from `${{ github.event.repository.description }}` to `${{ matrix.short }}`
- [ ] 1.4 Leave `readme-filepath: readme.md`, `needs: release-linux`, and `if: github.event_name == 'push' && !cancelled()` unchanged; confirm `fail-fast: false` remains
- [ ] 1.5 Confirm each `short` value is ≤100 bytes (Docker Hub short-description limit)

## 2. Verify

- [ ] 2.1 Lint the workflow (`gx` / `actionlint`) — green
- [ ] 2.2 After the next tag release, confirm all three `update-description` legs succeed (including `flutter-windows`)
- [ ] 2.3 Visually confirm on Docker Hub: each of the three repos shows the shared `readme.md` Overview and its platform-specific short description; `flutter-windows` now has an Overview
- [ ] 2.4 Confirm a `workflow_dispatch` Windows rebuild still reports `update-description` as `skipped`

## 3. Out of scope (tracking)

- [ ] 3.1 Docker Scout coverage for `flutter-windows` — same matrix omission in `record-image`; tracked in [issue #506](https://github.com/gmeligio/flutter-docker-image/issues/506), NOT part of this change
