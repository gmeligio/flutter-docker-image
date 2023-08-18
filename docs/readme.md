<!--- This markdown file was auto-generated from "readme.mdx" -->

[![channel](https://img.shields.io/static/v1?label=channel&message=stable&color=blue)](https://docs.flutter.dev/release/archive?tab=linux) [![flutter-android version](https://img.shields.io/docker/v/gmeligio/flutter-android?label=flutter-android%20version)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![flutter-android pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-android?label=flutter-android%20pulls)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![flutter-android size](https://img.shields.io/docker/image-size/gmeligio/flutter-android?label=flutter-android%20size)](https://hub.docker.com/r/gmeligio/flutter-android/tags)

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The source is available [on GitHub](https://github.com/gmeligio/flutter-docker-image).

The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

Features:

* \[x\] Installed Flutter SDK 3.13.0
* \[x\] Analytics disabled by default, opt-in suggested in the Docker entrypoint.
* \[x\] Rootless user `flutter:flutter`, with permissions to run on GitLab CI.
* \[x\] Cached Fastlane gem 2.214.0
* \[ \] Minimal image with predownloaded SDKs and tools ready to run `flutter` commands:  
   * \[x\] Android  
   * \[ \] iOS  
   * \[ \] Linux  
   * \[ \] Windows  
   * \[ \] Web

## Alpha stability

The images are experimental and are in active development. They are being used for small projects but there is no confirmation of production usage yet.

## flutter-android image

Predownloaded SDKs and tools:

* Licenses accepted
* Android SDK Platforms: 33
* Gradle: 7.5

Registries:

* https://hub.docker.com/r/gmeligio/flutter-android
* https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android
* https://quay.io/repository/gmeligio/flutter-android

TODO:

* \[ \] Android emulator
* \[ \] Android NDK

## Running containers

On the terminal:

```bash
# From Docker Hub
docker run --rm -it gmeligio/flutter-android:3.13.0 bash

# From GitHub Container Registry
docker run --rm -it ghcr.io/gmeligio/flutter-android:3.13.0 bash

# From Quay.io
docker run --rm -it quay.io/gmeligio/flutter-android:3.13.0 bash
```

On a workflow in GitHub Actions:

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ghcr.io/gmeligio/flutter-android:3.13.0
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Build
        run: flutter build apk
```

On a `.gitlab-ci.yml` in GitLab CI:

```yaml
build:
  image: ghcr.io/gmeligio/flutter-android:3.13.0
  script:
    - flutter build apk
```

Fastlane (see guide https://docs.fastlane.tools):

```bash
# Ruby bundler is available in the container.
# The fastlane gem is cached but not installed

# Use --prefer-local to download gems only if they are not cached
bundle install --prefer-local
bundle exec fastlane
```

## Versions

There is no `latest` Docker tag on purpose. You need to specify the version of the image you want to use. The reason for that is that `latest` is a dynamic tag that can be confusing when reading the image URI because doesn't necessarily point to the latest image built and can cause unexpected behavior when rerunning a past CI job that runs with an overwritten latest tags. There are multiple articles explaining more about this reasoning like [What's Wrong With The Docker :latest Tag?](https://vsupalov.com/docker-latest-tag/) and [The misunderstood Docker tag: latest](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).

The tag is composed of the Flutter version used to build the image. For example:

* Docker image: gmeligio/flutter-android:3.13.0
* Flutter version: 3.13.0

## Developing locally

### Running the container

The Dockerfile expects a few parameters:

* `flutter_version <string>`: The version of Flutter to use when building. Example: 3.13.0
* `android_build_tools_version <string>`: The version of the Android SDK Build Tools to install. Example: 30.0.3
* `android_platform_versions <list>`: The versions of the Android SDK Platforms to install, separated by spaces. Example: 28 31 33

```bash
# Android
docker build --target android --build-arg flutter_version=3.13.0 fastlane_version=2.214.0 android_build_tools_version=30.0.3 --build-arg android_platform_versions="33" -t android-test .
```

### Dockerfile stages

The base image is `debian/debian:11-slim` and from there multiple stages are created:

1. `flutter` stage hast only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
2. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.
3. `android-test` stage is for testing purposes. It creates a Flutter app and checks that the can be build for Android.

## FAQ

### Why not push to AWS ECR Public registry?

The storage of the images starts to cost after 50 GB and increases with every pushed image because the AWS Free Tier covers up to 50 GB of total storage for free in ECR Public.

## Other Docker projects for mobile development

* https://github.com/softartdev/docker-android-fastlane

## Acknowledgments

* https://github.com/mingchen/docker-android-build-box
* https://github.com/gmemstr/flutter-fastlane-android
* https://github.com/circleci/circleci-images
* https://github.com/cirruslabs/docker-images-android
* https://github.com/cirruslabs/docker-images-flutter
* https://github.com/instrumentisto/flutter-docker-image
* https://github.com/fischerscode/DockerFlutter

## License

[MIT License](../LICENSE)