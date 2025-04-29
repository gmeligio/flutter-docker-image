<!--- This markdown file was auto-generated from "readme.mdx" -->

[![openssf scorecard](https://api.scorecard.dev/projects/github.com/gmeligio/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/gmeligio/flutter-docker-image) [![channel](https://img.shields.io/static/v1?label=channel&message=stable&color=blue)](https://docs.flutter.dev/release/archive?tab=linux) [![flutter-android version](https://img.shields.io/docker/v/gmeligio/flutter-android?label=flutter-android%20version)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![flutter-android pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-android?label=flutter-android%20pulls)](https://hub.docker.com/r/gmeligio/flutter-android/tags)

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The source is available [on GitHub](https://github.com/gmeligio/flutter-docker-image).

The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

## Contents

* [Features](#features)
* [Running Containers](#running-containers)
* [Tags](#tags)
* [Building Locally](#building-locally)
* [Roadmap](#roadmap)
* [FAQ](#faq)  
   * [Why the images are not published in the AWS ECR Public registry?](#why-the-images-are-not-published-in-the-aws-ecr-public-registry)
* [Why there is no dynamic tag like latest?](#why-there-is-no-dynamic-tag-like-latest)
* [Contributing](#contributing)
* [License](#license)

## Features

* Installed Flutter SDK 3.29.3.
* Analytics disabled by default, opt-in if `ENABLE_ANALYTICS` environment variable is passed when running the container.
* Rootless user `flutter:flutter`, with permissions to run on Github workflows and GitLab CI.
* Minimal image with predownloaded SDKs and tools ready to run `flutter` commands for the Android platform.

Predownloaded SDKs and tools in Android:

* Licenses accepted
* Android SDK Platforms: 35
* Android NDK: 26.3.11579264
* Gradle: 8.10.2

## Running Containers

| Registry                  | flutter-android                                                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Docker Hub                | [gmeligio/flutter-android:3.29.3](https://hub.docker.com/r/gmeligio/flutter-android)                                       |
| GitHub Container Registry | [ghcr.io/gmeligio/flutter-android:3.29.3](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android) |
| Quay                      | [quay.io/gmeligio/flutter-android:3.29.3](https://quay.io/repository/gmeligio/flutter-android)                             |

On the terminal:

```bash
# From GitHub Container Registry
docker run --rm -it ghcr.io/gmeligio/flutter-android:3.29.3 bash
```

On a workflow in GitHub Actions:

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ghcr.io/gmeligio/flutter-android:3.29.3
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Build
        run: flutter build apk
```

On a `.gitlab-ci.yml` in GitLab CI:

```yaml
build:
  image: ghcr.io/gmeligio/flutter-android:3.29.3
  script:
    - flutter build apk
```

## Tags

Every new tag on the flutter stable channel gets built. The tag is composed of the Flutter version used to build the image:

* Docker image: gmeligio/flutter-android:3.29.3
* Flutter version: 3.29.3

## Building Locally

The android.Dockerfile expects a few arguments:

* `flutter_version <string>`: The version of Flutter to use when building. Example: 3.29.3
* `android_build_tools_version <string>`: The version of the Android SDK Build Tools to install. Example: 34.0.0
* `android_platform_versions <list>`: The versions of the Android SDK Platforms to install, separated by spaces. Example: 35

```bash
# Android
docker build --target android --build-arg flutter_version=3.29.3 --build-arg android_build_tools_version=34.0.0 --build-arg android_platform_versions="35" -t android-test .
```

## Roadmap

* Minimal image with predownloaded SDKs and tools ready to run `flutter` commands for the platforms:  
   * iOS  
   * Linux  
   * Windows  
   * Web
* Android features:  
   * Android emulator

## FAQ

### Why the images are not published in the AWS ECR Public registry?

The storage of the images starts to cost after 50 GB and increases with every pushed image because the AWS Free Tier covers up to 50 GB of total storage for free in ECR Public.

## Why there is no dynamic tag like `latest`?

There is no `latest` Docker tag on purpose. You need to specify the version of the image you want to use. The reason for that is that `latest` can cause unexpected behavior when rerunning a past CI job that was expected to use the old build of the `latest` tag. There are multiple articles explaining more about this reasoning like [What's Wrong With The Docker :latest Tag?](https://vsupalov.com/docker-latest-tag/) and [The misunderstood Docker tag: latest](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).

## Contributing

See [Contributing](docs/contributing.md).

## License

Flutter is licensed under [BSD 3-Clause "New" or "Revised" license](https://github.com/flutter/flutter/blob/master/LICENSE).

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.

The [sources](https://github.com/gmeligio/flutter-docker-image) for producing gmeligio/flutter-android Docker images are licensed under [MIT License](LICENSE.md).
