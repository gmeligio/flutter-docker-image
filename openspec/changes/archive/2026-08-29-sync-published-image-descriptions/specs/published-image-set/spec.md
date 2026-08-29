## ADDED Requirements

### Requirement: The published image set is declared once, as data

The set of images this project publishes SHALL be declared in a single
machine-readable manifest, `config/images.json`. Each entry SHALL carry the
properties that distinguish one image from another across the whole pipeline:
its published repository name, which Dockerfile it builds from, its Docker Hub
short description, and per-concern participation flags.

No workflow SHALL restate the image set as a literal list. Every job whose
`strategy.matrix` enumerates images SHALL derive that matrix from the manifest.

The experience context is the CI engineer who pulls `flutter-windows` and finds
it treated as a real published image everywhere — with a Docker Hub description,
a verified anonymous pull, and a documented reason wherever it is deliberately
left out. Before this requirement the image set was re-spelled by hand in about
twelve places, and a build-time exclusion (Windows is not built from
`android.Dockerfile`) was copy-pasted into a publication matrix, leaving
`gmeligio/flutter-windows` with a blank Docker Hub page for months while the job
that should have filled it reported success (issue #521). The same defect left
32 orphaned `flutter-web` PR tags in GHCR (issue #544).

#### Scenario: A newly added image reaches every concern by default

- **GIVEN** `config/images.json` declares images and every image matrix derives from it
- **WHEN** a new image entry is added to the manifest
- **THEN** the build, verify, and description-sync matrices each include the new image
- **AND** no workflow file needs a separate edit to list it

#### Scenario: Manifest is validated before any image is built

- **GIVEN** `config/images.json` is missing a required field for one of its entries
- **WHEN** any workflow job that reads a manifest runs
- **THEN** the `validate-version-manifest` step fails, naming the offending field and its JSON path
- **AND** the failure occurs before any `docker build` step starts

### Requirement: Participation in a concern is declared per image, with a reason

The manifest SHALL record each image's participation in a pipeline concern as an
explicit value rather than an absence, since an image may take part in some
concerns and not others. The schema SHALL pin exclusions that follow from a
platform limitation so they cannot be flipped silently.

Specifically: an image built from `windows.Dockerfile` SHALL declare `scout:
false`, because Docker Scout does not support Windows images, and `prTag:
false`, because its pull-request build pushes nothing that would later need
deleting. The schema SHALL reject a Windows image that claims either capability.
An image built from `android.Dockerfile` SHALL additionally declare its build
`target` and its container-structure-test config, which have no meaning for a
Windows image.

The experience context is the maintainer reading a three-image matrix and
needing to know whether the fourth image is missing on purpose. Before this
requirement, `record-image` omitted `flutter-windows` with no comment while
`cleanup-pr-image.yml` omitted it with a justification — the same kind of gap,
one marked and one not, and no way to tell an expired decision from an oversight.

#### Scenario: A Windows image cannot claim Scout coverage

- **GIVEN** a manifest entry that builds from `windows.Dockerfile`
- **WHEN** that entry sets `scout` to `true`
- **THEN** schema validation fails, reporting conflicting values for `scout`
- **AND** no job runs with the invalid manifest

#### Scenario: A Linux-built image must declare its build target and test config

- **GIVEN** a manifest entry that builds from `android.Dockerfile`
- **WHEN** that entry omits its build target or its test config
- **THEN** schema validation fails, naming the missing required field

#### Scenario: Excluded images are absent from the concerns they opt out of

- **GIVEN** a manifest in which `flutter-windows` declares `scout: false`
- **WHEN** the Scout recording job builds its matrix
- **THEN** the matrix contains every image declaring `scout: true`
- **AND** it does not contain `flutter-windows`

### Requirement: An empty image matrix fails loudly

A matrix derived from the manifest SHALL NOT be allowed to expand to zero legs.
The job that constructs a matrix SHALL fail when any filter yields an empty set,
and SHALL record the constructed matrix in its output so the set a run acted on
is recoverable from the run alone.

The experience context is the maintainer trusting a green check. A zero-leg
matrix expands to nothing and reports success, which is indistinguishable from
work having been done — the precise shape of issue #521, where
`update-description` passed for months while never touching `flutter-windows`.

#### Scenario: An empty filter result fails the run

- **GIVEN** a manifest edit that leaves one concern's filter matching no images
- **WHEN** the job constructing that matrix runs
- **THEN** the job fails, naming the concern whose filter matched nothing
- **AND** downstream jobs for that concern do not report success

#### Scenario: The constructed matrix is visible in the run

- **WHEN** a matrix is constructed from the manifest
- **THEN** the run records which images it contains
- **AND** a maintainer can tell from the run which images the concern acted on, without inspecting the manifest at that commit
