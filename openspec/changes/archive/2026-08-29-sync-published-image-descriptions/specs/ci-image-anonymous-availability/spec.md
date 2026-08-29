## MODIFIED Requirements

### Requirement: Released images are anonymously pullable from every registry they are published to

After a release run publishes images, the `release.yml` workflow SHALL verify
that each published `<registry>/<repository>:<version>` resolves **without any
registry credentials**, and SHALL fail the release run if any does not. The set
of verified pairs SHALL be exactly the set the run published: for every image in
the published image set whose release job succeeded, its three registry pairs.
That set SHALL be derived from `config/images.json` rather than enumerated in
this requirement, so that adding an image extends verification without a spec or
workflow edit.

The experience context is the CI engineer who copies a pull command out of the
readme — `docker pull ghcr.io/<org>/flutter-android:<version>` — and expects it
to work with no login. Before this requirement, a release whose GHCR package was
private published "successfully" and only a downstream consumer discovered the
tag was unreachable (issue #492). Naming images in the requirement text later
let it drift: it listed two while the workflow verified four.

#### Scenario: A private GHCR package fails the release

- **GIVEN** a release job pushed `ghcr.io/<org>/<image>:X.Y.Z`
- **AND** that GHCR package's visibility is Private
- **WHEN** the `verify-published` job runs
- **THEN** the anonymous manifest resolution for
  `ghcr.io/<org>/<image>:X.Y.Z` does not return success
- **AND** the `verify-published` job fails
- **AND** the release run is reported as failed, naming that exact
  `<registry>/<image>:<tag>`

#### Scenario: All published pairs are public

- **GIVEN** a release run published every image in the set to
  Docker Hub, GHCR, and Quay at tag `X.Y.Z`
- **AND** every one of those packages is anonymously pullable
- **WHEN** `verify-published` runs
- **THEN** each of the published `<registry>/<repository>:X.Y.Z` pairs resolves
  anonymously
- **AND** the `verify-published` job succeeds

#### Scenario: Verification covers a newly added image without a spec edit

- **GIVEN** a new image is added to `config/images.json` and published by a release run
- **WHEN** `verify-published` runs
- **THEN** its three registry pairs are among the verified set
