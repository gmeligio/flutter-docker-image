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

### Requirement: Verification reflects the unauthenticated consumer

The verification SHALL resolve each tag using only anonymous registry
authentication (a bearer token obtained without credentials, via the standard
`WWW-Authenticate` token handshake), never a logged-in session. The
`verify-published` job SHALL NOT perform a registry login for any registry. The
check SHALL resolve the image manifest (a request to the registry's
`/v2/<repo>/manifests/<tag>` endpoint) rather than pulling image layers.

The experience context is the maintainer trusting a green check: because the job
holds no credentials, a passing result means an unauthenticated `docker pull` of
that tag would succeed — it cannot pass on the strength of CI's own access.

#### Scenario: The verification job holds no credentials

- **GIVEN** the `verify-published` job
- **THEN** it contains no `docker/login-action` (or equivalent credentialed
  login) step for any registry
- **AND** it resolves each tag through the registry HTTP manifest API using a
  bearer token obtained without credentials

#### Scenario: Manifest is resolved, layers are not pulled

- **WHEN** `verify-published` checks `<registry>/<repository>:X.Y.Z`
- **THEN** it issues a manifest request (e.g. `HEAD /v2/<repo>/manifests/X.Y.Z`)
- **AND** it does not download the image's layer blobs

### Requirement: Verification coverage tracks what the run published

The set of `<registry>/<repository>` pairs verified SHALL equal the set the run
actually published. `verify-published` SHALL gate each image's checks on the
result of the release job that produces it, so that a partial or platform-scoped
release verifies only the images it published. `verify-published` SHALL NOT
introduce a `needs:` dependency between `release-linux` and `release-windows`.

The experience context is the maintainer recovering a single platform via
`workflow_dispatch` (Windows-only rebuild, Android skipped): the verification
must check what was rebuilt and not fail on the platform that was intentionally
not published in that run.

#### Scenario: workflow_dispatch verifies Windows only

- **GIVEN** `release.yml` is triggered via `workflow_dispatch`
- **AND** `release-linux` is skipped while `release-windows` succeeds
- **WHEN** `verify-published` runs
- **THEN** it verifies the three `flutter-windows:X.Y.Z` registry pairs
- **AND** it does not verify any `flutter-android` pair

#### Scenario: A Windows release failure does not cancel Android verification

- **GIVEN** a tag push where `release-linux` succeeds and `release-windows`
  fails
- **WHEN** `verify-published` runs (`if: always()`)
- **THEN** it verifies the three `flutter-android:X.Y.Z` registry pairs
- **AND** it does not verify `flutter-windows` pairs (that job did not publish)
- **AND** no `needs:` edge between `release-linux` and `release-windows` was
  introduced by adding `verify-published`
