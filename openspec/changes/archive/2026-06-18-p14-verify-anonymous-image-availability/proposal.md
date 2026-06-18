## Why

[Issue #492](https://github.com/gmeligio/flutter-docker-image/issues/492): a
consumer copied `ghcr.io/gmeligio/flutter-android:3.44.1` from the readme and
their CI failed with `unauthorized` (the GHCR package page 404s for anonymous
visitors). The image **is** published — `release.yml` fans `flutter-android`
out to Docker Hub, GHCR, and Quay on every tag (`release.yml:53-62`, added in
#443). The break is downstream of the push: the GHCR package is **private**.

Direct anonymous probes from outside the org confirm the asymmetry:

| Target | Anonymous result | Meaning |
|---|---|---|
| `hub.docker.com/.../flutter-android` | 117 tags returned | public |
| `ghcr.io/.../flutter-android:3.44.1` | **403 DENIED, "invalid token"** | **private package** |
| `ghcr.io/.../flutter-windows:3.44.1` | `200`, `tags:["3.44.1"]` | public package |
| `quay.io/.../flutter-android:3.44.1` | unverifiable from the dev environment (egress allowlist) | **unknown** |

The 403 is package-level, not tag-level: GHCR refuses to grant an anonymous pull
token at all. The release tag lives *inside* the package; the package itself is
private.

The asymmetry is structural, not random. `build.yml:142-154` pushes
`flutter-android:pr-<N>`, `:branch-<ref>`, and `:buildcache` to GHCR on every
PR, using `secrets.GITHUB_TOKEN`. A GHCR package first created by a
`GITHUB_TOKEN` push is **private by default**, and the default token cannot flip
package visibility ([GitHub docs: configuring a package's
visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)).
So `flutter-android` was born private from CI and never flipped. `flutter-windows`
has no PR-build GHCR push (`windows.yml` only loads locally), so it was first
created at release time and was set public.

The deeper gap: **a successful `docker push` in CI is not the same as
"anonymously consumable," and nothing in the pipeline tests the difference.** The
only `docker pull` of a release-shaped tag anywhere (`build.yml:258`) pulls
`pr-<N>` *with* a GHCR login. No step ever resolves a *released* tag *without*
credentials — the exact thing a readme reader does. That is why this regressed
silently for every release since #443 and was found by a user, not by CI.

This change is justified for a spec because it pins down a contract the
**CI engineer copying a pull command out of the readme** depends on: every image
the project releases must be anonymously pullable, by tag, from every registry it
publishes to — and a release that violates this must fail loudly instead of
looking green.

## What Changes

- **One-time ops step (documented, not automatable here):** set the GHCR
  `flutter-android` package visibility to **Public** and link it to the
  repository. The default `GITHUB_TOKEN` cannot do this; automating it would
  require a standing PAT with `write:packages` + admin stored as a secret — a
  permanent credential cost for a once-per-package action, which we reject (see
  Option C in design.md). The smoke check below makes the manual step
  self-evident: it fails until the flip is done.
  - Side effect: GHCR visibility is per-*package*, not per-tag, so making
    `flutter-android` public also exposes `:buildcache` and any live
    `pr-*`/`branch-*` tags. This is harmless — they are build artifacts of a
    public repo, and `cleanup-pr-image.yml` already GCs PR tags.

- **`script/verify_published_image.sh` (new):** resolves one
  `<registry>/<repository>:<tag>` manifest using **only anonymous registry auth**
  (the standard `WWW-Authenticate` → token → retry dance), via a `HEAD` on the
  manifests endpoint. No `docker pull` (the Android image is ~3 GB; the manifest
  is the part that returns 403 when private). One registry-agnostic code path
  covers Docker Hub, GHCR, and Quay. Exit 0 iff the tag is anonymously
  resolvable.

- **`.github/workflows/release.yml` — new `verify-published` job:** runs after
  `release-android` and `release-windows` with **no registry login**, and calls
  the script for every `<registry>/<repository>:<version>` the run actually
  published (Android pairs when `release-android` succeeded; Windows pairs when
  `release-windows` succeeded). Fails the release run if any is not anonymously
  resolvable. It introduces **no `needs:` coupling between** `release-android`
  and `release-windows` (preserves the `windows-image-release` parallelism
  guarantee).

- **No change** to what gets pushed, to the existing release/test/scan jobs, or
  to `release-android`/`release-windows` independence.

## Capabilities

### New Capabilities

- `ci-image-anonymous-availability`: the contract that every released image is
  anonymously pullable by tag from every registry it is published to, verified
  post-publish with an unauthenticated manifest resolution that fails the release
  run on violation.

## Impact

- **Affected files:** `.github/workflows/release.yml` (new job),
  `script/verify_published_image.sh` (new). No change to `build.yml`, `ci.yml`,
  `windows.yml`, or the Dockerfiles.
- **One-time manual action:** flip GHCR `flutter-android` to Public. Quay's true
  state is unknown from the dev environment; the first real run of
  `verify-published` is the instrument that settles it — and fixing Quay, if
  broken, is the same one-time visibility action on that registry.
- **Behavioral change for the maintainer:** a release that publishes an image
  consumers cannot anonymously pull now fails the run, naming the offending
  `<registry>/<image>:<tag>`. `verify-published` is a tripwire surfaced *after*
  the push, not a gate that blocks publishing (the push already happened) — its
  job is to make a broken consumer surface impossible to miss.
- **Behavioral change for image consumers:** none directly from the workflow;
  the consumer-visible fix is the one-time visibility flip. The job keeps it
  from regressing.
- **Risk:** registry token/manifest endpoints differ subtly across Docker Hub,
  GHCR, and Quay. Mitigation: the script uses the standard token-handshake
  protocol all three implement, and is exercised against all three on the first
  release run; the tasks include running it locally against the *current* release
  first, where it must report `ghcr.io/.../flutter-android` failing (reproducing
  #492) before the flip and passing after — a built-in correctness check.
- **Risk:** anonymous Docker Hub manifest reads are rate-limited. A handful of
  HEADs per release is far under any limit.

## Future Work

Investigated in this pass, intentionally deferred so each lands as its own change:

1. **Periodic re-verification.** A scheduled run of `verify-published` against
   the latest release would catch a package being flipped *back* to private (or a
   registry outage) between releases, not just at release time.
2. **Reconcile the readme's registry table.** The readme advertises Docker Hub,
   GHCR, and Quay equally for `flutter-android`; `flutter-windows` is published to
   all three but not listed. Aligning the advertised surface with the verified
   surface is a docs change, separable from this CI guardrail.
