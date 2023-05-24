<!--- This markdown file was auto-generated from "readme.mdx" -->

[![Docker Image Version (latest by date)](https://img.shields.io/docker/v/gmeligio/flutter-android?label=flutter-android%20version)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![Docker Pulls](https://img.shields.io/docker/pulls/gmeligio/flutter-android?label=flutter-android%20pulls)](https://hub.docker.com/r/gmeligio/flutter-android/tags) [![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/gmeligio/flutter-android?label=flutter-android%20size)](https://hub.docker.com/r/gmeligio/flutter-android/tags)

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

Features:

* \[x\] Analytics disabled by default, opt-in suggested in the Docker entrypoint.
* \[x\] Rootless user, is run with the user flutter:flutter
* \[ \] Minimal image to run Flutter in Continuous Integration (CI):  
   * \[x\] Android  
   * \[ \] iOS  
   * \[ \] Linux  
   * \[ \] Windows  
   * \[ \] Flutter

## Usage

On the terminal:

```bash
# From Docker Hub
docker run --rm -it gmeligio/flutter-android:3.10.1-8db2f603 bash

# From GitHub Container Registry
docker run --rm -it ghcr.io/gmeligio/flutter-android:3.10.1-8db2f603 bash

# From Quay.io
docker run --rm -it quay.io/gmeligio/flutter-android:3.10.1-8db2f603 bash

# From AWS ECR
docker run --rm -it public.ecr.aws/gmeligio/flutter-android:3.10.1-8db2f603 bash

```

On a workflow in GitHub Actions:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/gmeligio/flutter-android:3.10.1-8db2f603
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Build
        run: flutter build apk

```

On a `.gitlab-ci.yml` in GitLab CI:

```yaml
build:
  image: ghcr.io/gmeligio/flutter-android:3.10.1-8db2f603
  script:
    - flutter build apk

```

## Versions

There is no `latest` Docker tag on purpose. You need to specify the version of the image you want to use.

The tag is composed of the Flutter version used and the first eight characters of this repository's commit SHA used to build the image. For example:

* tag: gmeligio/flutter-android:3.10.1-8db2f603
* Flutter version: 3.10.1
* commit SHA: 8db2f603

### flutter-android

Versions used in latest image:

* Flutter: 3.10.1
* Android SDK Platforms: 33
* Gradle: 7.5

Registries:

* https://hub.docker.com/r/gmeligio/flutter-android
* https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android
* https://quay.io/repository/gmeligio/flutter-android
* https://gallery.ecr.aws/gmeligio/flutter-android

## Alpha stability

The images are experimental and are in active development. They are being used for small projects but there is no confirmation of production usage yet.

## Developing locally

### Running the container

The Dockerfile expects a few parameters:

* `flutter_version <string>`: The version of Flutter to use when building. Example: 3.10.1
* `android_build_tools_version <string>`: The version of the Android SDK Build Tools to install. Example: 30.0.3
* `android_platform_versions <list>`: The versions of the Android SDK Platforms to install, separated by spaces. Example: 28 31 33

```bash
# Android
docker build --target android --build-arg flutter_version=3.7.4 android_build_tools_version=30.0.3 --build-arg android_platform_versions="28 31 33" -t android-test .

```

### Dockerfile stages

1. `flutter` stage hast only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
2. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.
3. `android-test` stage is for testing purposes. It creates a Flutter app and checks that the can be build for Android.

## TODO

1. Different images for different use cases of Flutter.  
   * By platform: Linux, Windows  
   * By tool: Fastlane  
   * By SDK: Android SDK,Adroid NDK
2. Android emulator

## Inspiration and related projects

* https://github.dev/circleci/circleci-images
* https://github.dev/cirruslabs/docker-images-android
* https://github.dev/cirruslabs/docker-images-flutter
* https://github.dev/instrumentisto/flutter-docker-image
* https://github.dev/mingchen/docker-android-build-box
* https://github.dev/gmemstr/flutter-fastlane-android
* https://github.dev/fischerscode/DockerFlutter

## License

[MIT License](../LICENSE)