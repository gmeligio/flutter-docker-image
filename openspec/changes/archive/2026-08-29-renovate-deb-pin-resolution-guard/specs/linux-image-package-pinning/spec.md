## MODIFIED Requirements

### Requirement: Each apt pin resolves against the same set of Debian suites the image enables

Every `deb`-datasource pin SHALL be resolved against the Debian suites from which the
installing image stage can install it — at minimum the base suite and its `-security` suite —
expressed as a list of `registryUrls` on a `packageRules` entry in `.github/renovate.json`.
Each `registryUrls` entry SHALL mirror a `Types`/`URIs`/`Suites`/`Components` stanza of the
image's real apt sources, in both suite and component list. Suite selection SHALL NOT be
expressed via `registryUrlTemplate`, which renders a single URL and therefore cannot address a
set.

Where a listed suite cannot currently be fetched by Renovate, the configuration SHALL record
why in its `description`, naming the upstream limitation, so that a maintainer reading the
config can tell an intentional gap from an oversight.

**Experience context:** A CI engineer trusts that a Renovate PR bumping an apt pin produces a
version the image can actually install. apt picks the highest version across every enabled
suite, so if Renovate watches fewer suites than apt, the two disagree about what "latest" is.

`-security` is load-bearing, not merely a currency concern. The only installable version of
`openjdk-17-jdk-headless` is `17.0.20.1+1-1~deb12u1`, published in `bookworm-security` and
nowhere else: a security upload moved `openjdk-17-jre-headless` there, and the JDK's strict
`Depends: openjdk-17-jre-headless (= <same version>)` forces the JDK to follow. A configuration
omitting the `-security` suite would state that the pin comes from somewhere it does not, and
could never propose the version the image needs.

Renovate cannot currently fetch those suites: its deb datasource hardcodes
`const compression = 'gz'`, and Debian publishes only `Packages` and `Packages.xz` on
`-security` and `-updates`, so each such URL returns 404 on every run — swallowed at debug
level while the job reports success. This is upstream renovate#44330; no repository
configuration works around it, and no mirror still carries the `.gz`. The `-security` entries
are kept regardless, because they state correctly where the pin resolves from and will resume
working with no edit once upstream lands `.xz`. The `-updates` entries are dropped: they are
equally unfetchable and no current pin resolves from them, so they assert coverage with no
corresponding need.

While that gap persists, Renovate cannot be relied on to notice a pin that has stopped being
installable. What catches it is the image build itself: editing a pin changes the Dockerfile,
which invalidates the build cache and re-runs `apt-get install`, so a bad pin fails the PR that
introduces it. A pin can still rot with no repo change — a later security upload moves apt's
candidate — and that break surfaces on the next PR to touch the file rather than when it
happens. That delay is accepted.

#### Scenario: A pin is resolved against the base and security suites of its family

- **GIVEN** an apt pin in `android.Dockerfile` installed from a suite the image enables
- **WHEN** a maintainer reads the configured `registryUrls` for that pin
- **THEN** they name the base suite and its `-security` suite
- **AND** together they describe where apt actually resolves the package from

#### Scenario: A pin installed from an added repository resolves against that repository

- **GIVEN** `openjdk-17-jdk-headless`, which the android stage installs after adding `config/debian_12_bookworm.sources`
- **WHEN** Renovate looks it up
- **THEN** it queries the bookworm suites named in that sources file, not the base image's trixie suites

#### Scenario: A known upstream fetch limitation is documented, not silent

- **GIVEN** a configured suite Renovate cannot currently fetch
- **WHEN** a maintainer reads the deb `packageRules` in `.github/renovate.json`
- **THEN** the `description` names the upstream limitation preventing it from being fetched
- **AND** the entry is recognisable as an intentional gap rather than a stale mistake

#### Scenario: A pin edited to an uninstallable version fails its own pull request

- **GIVEN** a pull request that changes an apt pin to a version apt cannot install
- **WHEN** the image is built for that pull request
- **THEN** the changed Dockerfile invalidates the build cache, `apt-get install` re-runs, and the build fails
- **AND** the failure names the version and the unmet dependency, so the pin is corrected before merge

#### Scenario: Suites are named by codename, not by a moving alias

- **GIVEN** the deb `packageRules` in `.github/renovate.json`
- **WHEN** a maintainer reads the configured suites
- **THEN** each names a Debian codename (e.g. `trixie`, `bookworm-security`)
- **AND** none uses a floating alias such as `stable` or `oldstable`, which would silently retarget every pin when Debian promotes a new release
