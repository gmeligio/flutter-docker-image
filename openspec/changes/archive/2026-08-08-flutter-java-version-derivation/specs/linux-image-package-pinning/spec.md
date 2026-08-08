## MODIFIED Requirements

### Requirement: Self-pinned image version values are declared with `ARG`, never `ENV`

Every Renovate-managed `*_VERSION` value in `android.Dockerfile` — a value carrying a `# renovate:` annotation and a literal default — SHALL be declared with `ARG`, not `ENV`. The `matchStrings` regex SHALL remain `ARG`-only, so the convention is enforced by what Renovate can match: an `ENV`-declared pin is invisible to the manager and therefore a defect.

A runtime environment variable MAY interpolate a build argument into its value
(for example `JAVA_HOME="/usr/lib/jvm/java-${android_java_version}-openjdk-amd64"`).
This does not violate the convention: the version is still `ARG`-declared and
Renovate-visible where it is managed, and the `ENV` is a derived runtime path
rather than a second pin. Such an `ENV` SHALL NOT introduce a literal version that
duplicates a value already carried by a build argument, and the interpolated `ARG`
SHALL be declared before the `ENV` that consumes it.

The allowance is bounded on both sides, and the boundary is the point of the
requirement rather than an incidental consequence of it. An `ENV` MAY interpolate
an `ARG` only when **both** hold: the `ENV` is a runtime path or setting the image
must expose for a tool to function, and the `ARG` it interpolates is not itself a
Renovate-managed `*_VERSION` pin. A `# renovate:`-annotated pin SHALL NOT reach an
`ENV` by any route — neither as a literal nor by interpolation. Interpolating one
would put the pin in the image's `Env` and in `docker inspect` output, which is
exactly what the `ARG`-only rule exists to prevent; the rule would otherwise be
trivially circumventable by wrapping the pin in an `ENV`.

`JAVA_HOME` satisfies both conditions: Gradle and the Android toolchain read it
from the environment, and `android_java_version` is a major supplied from the
manifest via `--build-arg`, not a pin. `OPENJDK_17_JDK_HEADLESS_VERSION` satisfies
neither and stays confined to the `RUN` that consumes it, as do the other eight
apt pins.

**Experience context:** A maintainer reading `android.Dockerfile` sees one keyword convention for self-pinned versions, with no `ENV` exceptions to explain. Build-only version strings do not leak into the final image's runtime environment or `docker inspect` metadata, and cannot collide with a real runtime variable a tool might read from the environment. Runtime variables that a tool genuinely needs — `JAVA_HOME` is read by Gradle and the Android toolchain — remain `ENV`, but derive their version component from the build argument rather than restating it, so the image cannot ship a `JAVA_HOME` pointing at a JDK major different from the one installed. The uppercase/lowercase `ARG` distinction is preserved and orthogonal: UPPERCASE-with-default names are self-pinned and Renovate-managed; lowercase names without a default are injected at build time via `--build-arg` from CI and are intentionally outside Renovate's scope.

#### Scenario: A managed version pin uses ARG

- **GIVEN** any `# renovate:`-annotated `*_VERSION` value in `android.Dockerfile`
- **WHEN** a maintainer reads its declaration
- **THEN** it is declared with `ARG`
- **AND** no `# renovate:`-annotated `*_VERSION` value is declared with `ENV`

#### Scenario: Build-only version does not persist into the image

- **GIVEN** the built Linux image
- **WHEN** a maintainer runs `docker inspect` on it
- **THEN** no `*_VERSION` apt-package pin appears in the image's `Env` configuration

#### Scenario: Externally injected build args keep the lowercase convention

- **GIVEN** a build argument supplied at build time via `--build-arg` (e.g. `flutter_version`, `fastlane_version`)
- **WHEN** a maintainer reads its declaration
- **THEN** it is a lowercase `ARG` with no default value and no `# renovate:` annotation
- **AND** Renovate does not attempt to manage it

#### Scenario: Runtime path derives its version from a build argument

- **GIVEN** `android.Dockerfile` declares `ARG android_java_version` supplied via `--build-arg`
- **WHEN** a maintainer reads the `JAVA_HOME` assignment
- **THEN** it interpolates `${android_java_version}` rather than a literal JDK major
- **AND** the `ARG` is declared before the `ENV` that consumes it
- **AND** the built image's `JAVA_HOME` resolves to the JDK major that was actually installed

#### Scenario: A managed pin cannot reach ENV by interpolation

- **GIVEN** a `# renovate:`-annotated `*_VERSION` `ARG` such as `OPENJDK_17_JDK_HEADLESS_VERSION`
- **WHEN** a maintainer reads `android.Dockerfile`
- **THEN** no `ENV` interpolates it
- **AND** it appears only in the `RUN` instruction that consumes it
- **AND** `docker inspect` on the built image shows it in neither `Env` nor any derived `Env` value

#### Scenario: No literal duplicates a build-argument value

- **GIVEN** a version value carried by a build argument
- **WHEN** a maintainer greps `android.Dockerfile` for that version as a literal
- **THEN** it appears only in the Renovate-managed `ARG` default, if at all
- **AND** no `ENV` restates it
