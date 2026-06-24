## ADDED Requirements

### Requirement: Every published image's Docker Hub description is synced on release

When a tag matching `*` is pushed, the `update-description` job in `.github/workflows/release.yml` SHALL sync the Docker Hub repository metadata for **every** published image — `flutter-android`, `flutter-web`, and `flutter-windows` — setting the full description (Overview) from the shared `readme.md` and a per-image short description. The job SHALL cover all three images via a single matrix and SHALL NOT omit `flutter-windows`.

The experience context is the CI engineer browsing Docker Hub who opens `<org>/flutter-windows` and expects an Overview explaining the image, the same as `<org>/flutter-android` — before this requirement, `flutter-windows` showed no Overview at all because the sync job skipped it.

#### Scenario: All three repositories receive the shared Overview

- **GIVEN** a tag `X.Y.Z` is pushed
- **WHEN** the `update-description` job completes
- **THEN** the Docker Hub `<org>/flutter-android`, `<org>/flutter-web`, and `<org>/flutter-windows` repositories each show the Overview rendered from `readme.md`
- **AND** the `flutter-windows` repository's Overview is no longer empty

#### Scenario: One image's sync failure does not skip the others

- **GIVEN** a tag is pushed
- **AND** the description sync for one image fails (e.g., a transient Docker Hub API error)
- **WHEN** the `update-description` job runs
- **THEN** the other images' descriptions are still synced
- **AND** the failed image surfaces as its own named matrix leg

### Requirement: Short descriptions are platform-specific and durable

Each image's Docker Hub short description SHALL state the platform the image targets and SHALL be authored in version control (carried on the workflow matrix), not sourced from the repository's generic "About" field. Re-running a release SHALL re-apply the same per-image short description rather than overwriting it with a generic value. Each short description SHALL be at most 100 bytes (the Docker Hub limit).

The experience context is the CI engineer scanning Docker Hub search results: `flutter-android`, `flutter-web`, and `flutter-windows` each show a distinct one-liner naming their platform, instead of an identical generic blurb — and a maintainer's wording is not silently reverted on the next release.

#### Scenario: Each repository shows a distinct, platform-naming short description

- **GIVEN** a release has run for tag `X.Y.Z`
- **WHEN** the three Docker Hub repositories are viewed
- **THEN** `flutter-android`'s short description names Android
- **AND** `flutter-web`'s short description names web
- **AND** `flutter-windows`'s short description names Windows
- **AND** no two of them are identical

#### Scenario: Short descriptions survive a re-release

- **GIVEN** the per-image short descriptions are set by a release
- **WHEN** a later tag is released
- **THEN** each repository still shows its platform-specific short description
- **AND** none has been replaced by the repository's generic "About" text
