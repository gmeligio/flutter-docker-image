# docker-hub-description-sync Specification

## Purpose

Define how each published image's Docker Hub page gets its description: which
repositories receive one, when the sync runs relative to the release jobs, and
how a per-image short description is preserved rather than overwritten by a
repository-wide default. The experience context is the CI engineer evaluating an
image on Docker Hub — the project's primary discovery surface for someone who
has not found the GitHub repository.

## Requirements

### Requirement: Every published image gets a Docker Hub description

On a tag push, the `release.yml` workflow SHALL publish a full description to
the Docker Hub repository of **every** image in the published image set,
including `flutter-windows`. The set of repositories receiving a description
SHALL be derived from `config/images.json`, not restated as a literal matrix.

The full description pushed SHALL be the generated `readme.md` — the same file
used as the GitHub repository README. (This rule previously lived inside the
`generated-docs-and-examples` capability, which could not express the rest of
the publication behavior specified here.)

The experience context is the CI engineer evaluating an image on Docker Hub —
the project's primary discovery surface for someone who has not found the GitHub
repo. Before this requirement, `gmeligio/flutter-windows` showed a blank page
below its one-line tagline while `flutter-android` and `flutter-web` showed the
generated readme, because the description matrix was copy-pasted from the build
matrix, which excludes Windows for an unrelated build reason (issue #521).

#### Scenario: The Windows image page shows a description

- **GIVEN** a tag `X.Y.Z` is pushed and the release jobs succeed
- **WHEN** the description-sync job completes
- **THEN** the Docker Hub API reports a non-null `full_description` for `flutter-windows`
- **AND** the same holds for every other image in the published set

#### Scenario: A new image is described without a workflow edit

- **GIVEN** a new image is added to `config/images.json`
- **WHEN** the next tag is pushed
- **THEN** that image's Docker Hub repository receives a full description
- **AND** no change to `release.yml` was required to include it

### Requirement: An image's short description is its own, and is never overwritten by a repository-wide default

The short description pushed to an image's Docker Hub repository SHALL come from
that image's entry in `config/images.json`. The sync SHALL NOT source the short
description from the GitHub repository description, because a repository-wide
value cannot describe a specific image and would replace a more accurate one.

The experience context is the reader scanning Docker Hub search results, where
the short description is often the only text shown. `gmeligio/flutter-windows`
carries `"Docker images for Flutter CI in Windows platform"`, which says more
than the repository-wide `"Docker images for Flutter Continuous Integration
(CI)"`. The sync action sends the short description on every call, so adding
Windows to the matrix without this requirement would have made the one field
where the Windows page was better than the others worse.

#### Scenario: A tailored short description survives the sync

- **GIVEN** `flutter-windows` declares a short description naming the Windows platform
- **WHEN** the description-sync job runs for `flutter-windows`
- **THEN** the Docker Hub short description for that repository is the declared one
- **AND** it is not replaced by the GitHub repository description

#### Scenario: Each image's short description is independent

- **WHEN** the description-sync job runs for every image in the set
- **THEN** each repository receives the short description declared for that image
- **AND** changing one image's short description does not alter another's

### Requirement: A description is only synced for an image whose release succeeded

The description-sync job SHALL depend on every job that publishes an image in
the set, so that no description is synced for an image that failed to publish. A
failure to publish one image SHALL NOT prevent the descriptions of successfully
published images from syncing.

The experience context is the maintainer reading a release run: a description
that updated for an image that never shipped is a false signal about what was
released. Before this requirement the sync depended only on the Linux release
job, so a Windows build failure was invisible to it.

#### Scenario: A failed image build blocks only its own description

- **GIVEN** a tag push where the Windows release job fails and the Linux release job succeeds
- **WHEN** the description-sync job runs
- **THEN** the descriptions of the successfully published images are still synced
- **AND** the run does not report a successful description sync for the image that failed to publish

#### Scenario: Sync failure is attributable to one image

- **GIVEN** the Docker Hub API rejects the update for exactly one image
- **WHEN** the description-sync job runs
- **THEN** the failing job leg is identifiable by the image it was syncing
- **AND** the other images' descriptions are still synced
