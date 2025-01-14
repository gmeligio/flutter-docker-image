<!--- This markdown file was auto-generated from "readme.mdx" -->

[![openssf scorecard](https://api.scorecard.dev/projects/github.com/gmeligio/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/gmeligio/flutter-docker-image) [![channel](https://img.shields.io/static/v1?label=channel&message=stable&color=blue)](https://docs.flutter.dev/release/archive?tab=linux) [![flutter-android version](https://img.shields.io/docker/v/gmeligio/flutter-android?label=flutter-android%20version)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![flutter-android pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-android?label=flutter-android%20pulls)](https://hub.docker.com/r/gmeligio/flutter-android/tags)

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The source is available [on GitHub](https://github.com/gmeligio/flutter-docker-image).

The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

## Features

* Installed Flutter SDK 3.27.2.
* Analytics disabled by default, opt-in if `ENABLE_ANALYTICS` environment variable is passed when running the container.
* Rootless user `flutter:flutter`, with permissions to run on Github workflows and GitLab CI.
* Cached Fastlane gem 2.226.0.
* Minimal image with predownloaded SDKs and tools ready to run `flutter` commands for the Android platform.

Predownloaded SDKs and tools in Android:

* Licenses accepted
* Android SDK Platforms: 35
* Gradle: 8.3

## Alpha Stability

The images are experimental and are in active development. They are being used for small projects but there is no confirmation of production usage yet.

## Running Containers

Registries:

* [Docker Hub](https://hub.docker.com/r/gmeligio/flutter-android)
* [Github Container Registry](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android)
* [Quay](https://quay.io/repository/gmeligio/flutter-android)

On the terminal:

```bash
# From Docker Hub
docker run --rm -it gmeligio/flutter-android:3.27.2 bash

# From GitHub Container Registry
docker run --rm -it ghcr.io/gmeligio/flutter-android:3.27.2 bash

# From Quay.io
docker run --rm -it quay.io/gmeligio/flutter-android:3.27.2 bash
```

On a workflow in GitHub Actions:

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ghcr.io/gmeligio/flutter-android:3.27.2
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Build
        run: flutter build apk
```

On a `.gitlab-ci.yml` in GitLab CI:

```yaml
build:
  image: ghcr.io/gmeligio/flutter-android:3.27.2
  script:
    - flutter build apk
```

Fastlane:

```bash
# Ruby bundler is available in the container.
# The fastlane gem is cached but not installed
# For more information, see https://docs.fastlane.tools

# Use --prefer-local to download gems only if they are not cached
bundle install --prefer-local
bundle exec fastlane
```

## Versions

There is no `latest` Docker tag on purpose. You need to specify the version of the image you want to use. The reason for that is that `latest` is a dynamic tag that can be confusing when reading the image URI because doesn't necessarily point to the latest image built and can cause unexpected behavior when rerunning a past CI job that runs with an overwritten latest tags. There are multiple articles explaining more about this reasoning like [What's Wrong With The Docker :latest Tag?](https://vsupalov.com/docker-latest-tag/) and [The misunderstood Docker tag: latest](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).

The tag is composed of the Flutter version used to build the image. For example:

* Docker image: gmeligio/flutter-android:3.27.2
* Flutter version: 3.27.2

## Developing Locally

### Running The Container

The Dockerfile expects a few parameters:

* `flutter_version <string>`: The version of Flutter to use when building. Example: 3.27.2
* `android_build_tools_version <string>`: The version of the Android SDK Build Tools to install. Example: 33.0.1
* `android_platform_versions <list>`: The versions of the Android SDK Platforms to install, separated by spaces. Example: 28 31 33

```bash
# Android
docker build --target android --build-arg flutter_version=3.27.2 --build-arg fastlane_version=2.226.0 --build-arg android_build_tools_version=33.0.1 --build-arg android_platform_versions="35" -t android-test .
```

### Dockerfile stages

The base image is `debian/debian:12-slim` and from there multiple stages are created:

1. `flutter` stage hast only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
2. `fastlane` stage has the dependencies required to install fastlane but doesn't install fastlane.
3. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.

## Roadmap

* Minimal image with predownloaded SDKs and tools ready to run `flutter` commands for the platforms:  
   * \[ \] iOS  
   * \[ \] Linux  
   * \[ \] Windows  
   * \[ \] Web
* Android features:  
   * \[ \] Android emulator  
   * \[ \] Android NDK

## FAQ

### Why the images are not published in the AWS ECR Public registry?

The storage of the images starts to cost after 50 GB and increases with every pushed image because the AWS Free Tier covers up to 50 GB of total storage for free in ECR Public.

## Contributing

See [Contributing](docs/contributing.md).

## Other Docker projects for mobile development

* [docker-android-fastlane](https://github.com/softartdev/docker-android-fastlane)

## Acknowledgments

* [docker-android-build-box](https://github.com/mingchen/docker-android-build-box)
* [flutter-fastlane-android](https://github.com/gmemstr/flutter-fastlane-android)
* [circleci-images](https://github.com/circleci/circleci-images)
* [docker-images-android](https://github.com/cirruslabs/docker-images-android)
* [docker-images-flutter](https://github.com/cirruslabs/docker-images-flutter)
* [flutter-docker-image](https://github.com/instrumentisto/flutter-docker-image)
* [DockerFlutter](https://github.com/fischerscode/DockerFlutter)

## License

[MIT License](LICENSE.md)