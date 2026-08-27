## MODIFIED Requirements

### Requirement: Build job exposes a handoff for downstream jobs

The CI job that builds the Flutter Docker image SHALL expose three job outputs that downstream jobs in the same workflow run can consume to access the image without rebuilding it. The build job runs one leg per image declaring a pull-request handoff tag in `config/images.json`, and each leg's outputs SHALL name **that leg's image**, not a fixed one:

- `image_ref`: the full registry reference (`ghcr.io/<owner>/<image>:<tag>`) when the build pushed to GHCR; empty string otherwise.
- `image_artifact`: the artifact name (`image-<run_id>`) when the build uploaded a `docker save` tarball instead; empty string otherwise.
- `image_local_tag`: the tag the image carries in the local docker daemon (and inside the artifact tarball) — `<image>:<flutter-version>`. Always set, regardless of handoff channel.

Exactly one of `image_ref` and `image_artifact` SHALL be non-empty per run; `image_local_tag` SHALL always be non-empty. A consumer SHALL be able to decide its pull strategy from the outputs alone, without inspecting `github.event` itself.

The experience context is a maintainer adding a new validation step in a later change — they look at the build job's outputs, see exactly one handoff channel populated, and write a single consumer that branches on which channel. The `image_local_tag` output lets fork-path consumers reference the image by its loaded tag without recomputing it from the version manifest.

Naming a single image in this requirement is what made it contradict `web-image-testing`, which already asserts that `flutter-web` handoff tags exist. Every image declaring a handoff tag produces these outputs (issue #544).

#### Scenario: Outputs encode the handoff kind unambiguously

- **GIVEN** any successful build run
- **WHEN** the run completes
- **THEN** exactly one of `image_ref` and `image_artifact` is non-empty
- **AND** the non-empty one matches the documented format (`ghcr.io/<owner>/<image>:pr-<N>` / `ghcr.io/<owner>/<image>:branch-<branch>` or `image-<run_id>`)
- **AND** `image_local_tag` is non-empty and matches `<image>:<flutter-version>`

#### Scenario: Every image declaring a handoff tag produces outputs naming itself

- **GIVEN** `config/images.json` declares more than one image with a pull-request handoff tag
- **WHEN** the build job runs its legs
- **THEN** each leg's `image_ref` and `image_local_tag` name that leg's own image
- **AND** no leg reports outputs naming a different image

#### Scenario: An image that pushes nothing on a pull request declares no handoff tag

- **GIVEN** an image whose pull-request build does not push to a registry
- **WHEN** the set of handoff-tag producers is derived from the manifest
- **THEN** that image is absent from it
- **AND** no cleanup is attempted for a tag it never created
