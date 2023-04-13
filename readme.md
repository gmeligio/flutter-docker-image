<!-- Update badges with links to Docker images -->
# Docker images for Flutter Continuous Integration (CI)

## Available images

- https://hub.docker.com/r/gmeligio/flutter-android
- https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android
- https://quay.io/repository/gmeligio/flutter-android
- https://gallery.ecr.aws/gmeligio/flutter-android

## Features

- [x] Analytics disabled by default
- [x] Rootless user in Docker images
- [ ] Minimal image to run Flutter in Continuous Integration (CI):
    - [x] Android
    - [ ] iOS
    - [ ] Linux
    - [ ] Windows
    - [ ] Flutter

## Alpha stability

The images are experimental and are in active development. They are being used for small projects but there is no confirmation of production usage yet.

## Running locally the Docker image

1. Build the image
    
```bash
# Android
docker build --target android --build-arg flutter_version=3.7.4 android_build_tools_version=30.0.3 --build-arg android_platform_versions="28 31 33" -t android-test .
```

## TODO

1. Different images for different use cases of Flutter.
    - By platform: Linux, Windows
    - By tool: Fastlane
    - By SDK: Android SDK,Adroid NDK
1. Add renovate.json to update packages:
    - [ ] apt in Docker images
