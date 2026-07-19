<!--- This markdown file was auto-generated from docs/build.mjs -->

[![openssf scorecard](https://api.scorecard.dev/projects/github.com/gmeligio/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/gmeligio/flutter-docker-image) [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/gmeligio/flutter-docker-image) [![version](https://img.shields.io/static/v1?label=version&message=3.44.6&color=blue)](https://docs.flutter.dev/release/archive?tab=linux) [![channel](https://img.shields.io/static/v1?label=channel&message=stable&color=blue)](https://docs.flutter.dev/release/archive?tab=linux) [![flutter-android pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-android?label=flutter-android%20pulls)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![flutter-web pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-web?label=flutter-web%20pulls)](https://hub.docker.com/r/gmeligio/flutter-web/tags) [![flutter-windows pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-windows?label=flutter-windows%20pulls)](https://hub.docker.com/r/gmeligio/flutter-windows/tags)

# Flutter Docker Image

Minimal Docker images for building Flutter apps in CI — Android, Web, and Windows, with the SDK and toolchain predownloaded so `flutter` runs without extra downloads. Images track the Flutter **stable** channel; the current version is **3.44.6**.

```bash
docker run --rm -it ghcr.io/gmeligio/flutter-android:3.44.6 flutter build apk
```

Each image is tagged with the Flutter version it ships (`:3.44.6`); there is no `latest` tag ([why](docs/faq.md#why-there-is-no-dynamic-tag-like-latest)). Images run analytics-disabled by default (opt in with `ENABLE_ANALYTICS=true`) as a rootless `flutter` user.

## Images

| Image | Platform | Build command |
| ----- | -------- | ------------- |
| `flutter-android` | Android | `flutter build apk` |
| `flutter-web` | Web | `flutter build web` |
| `flutter-windows` | Windows | `flutter build windows` |

### flutter-android

| Registry                  | flutter-android |
| ------------------------- | --------------- |
| Docker Hub                | [gmeligio/flutter-android:3.44.6](https://hub.docker.com/r/gmeligio/flutter-android) |
| GitHub Container Registry | [ghcr.io/gmeligio/flutter-android:3.44.6](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android) |
| Quay                      | [quay.io/gmeligio/flutter-android:3.44.6](https://quay.io/repository/gmeligio/flutter-android) |

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ghcr.io/gmeligio/flutter-android:3.44.6
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build
        run: flutter build apk
```

### flutter-web

| Registry                  | flutter-web |
| ------------------------- | --------------- |
| Docker Hub                | [gmeligio/flutter-web:3.44.6](https://hub.docker.com/r/gmeligio/flutter-web) |
| GitHub Container Registry | [ghcr.io/gmeligio/flutter-web:3.44.6](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-web) |
| Quay                      | [quay.io/gmeligio/flutter-web:3.44.6](https://quay.io/repository/gmeligio/flutter-web) |

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ghcr.io/gmeligio/flutter-web:3.44.6
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build
        run: flutter build web
```

### flutter-windows

Windows containers cannot run under the Linux `container:` field, so run on a `windows-2025` runner and invoke `docker` directly.

| Registry                  | flutter-windows |
| ------------------------- | --------------- |
| Docker Hub                | [gmeligio/flutter-windows:3.44.6](https://hub.docker.com/r/gmeligio/flutter-windows) |
| GitHub Container Registry | [ghcr.io/gmeligio/flutter-windows:3.44.6](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-windows) |
| Quay                      | [quay.io/gmeligio/flutter-windows:3.44.6](https://quay.io/repository/gmeligio/flutter-windows) |

```yaml
jobs:
  build:
    runs-on: windows-2025
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build
        run: docker run --rm -v ${{ github.workspace }}:C:\app -w C:\app ghcr.io/gmeligio/flutter-windows:3.44.6 flutter build windows
```

## CI backends

These images run on GitHub Actions, GitLab CI, Gitea, and Forgejo. Ready-to-use workflows for each backend are in [`examples/`](examples/) — the Gitea and Forgejo ones show how to make Node.js available for `actions/checkout` (act-based runners do not inject it the way GitHub does).

## More

* [Building the images locally](docs/contributing.md#building-the-images-locally)
* [FAQ](docs/faq.md)
* [Contributing](docs/contributing.md)

## License

Flutter is licensed under [BSD 3-Clause "New" or "Revised" license](https://github.com/flutter/flutter/blob/master/LICENSE).

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.

The [sources](https://github.com/gmeligio/flutter-docker-image) for producing these Docker images are licensed under [MIT License](LICENSE.md).
