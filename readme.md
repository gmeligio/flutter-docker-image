# Docker image for Flutter

## Alpha stability

This package is experimental and it's in active development

## Usage

There are different images for different use cases of Flutter.

By platform:
- [ ] Linux: Ubuntu
- [ ] Windows

By tool:
- [ ] Fastlane

By SDK:
- [ ] Android SDK
- [ ] Android NDK

## TODO:

1. Get versions from https://github.com/flutter/flutter/blob/master/packages/flutter_tools/gradle/flutter.gradle
1. Add renovate.json to update packages:
    - [ ] apt in Docker images
1. Use non-root user in Docker images

## Versions

- [ ] Latest two minor versions of Flutter, according to the [stable channel](https://flutter.dev/docs/development/tools/sdk/releases)
- [ ] Java version: OpenJDK 11
- [ ] Latest Android SDK Command-Line Tools version:
- [ ] Latest Android SDK:
- [ ] Latest Android NDK:
- [ ] Latest Fastlane: 
- [ ] Latest Android Gradle plugin from default Flutter version:

## Usage

- From Docker Hub

```bash
docker pull gmeligio/flutter:0.10.3-tf1.1.9-node16.15.0-alpine3.15
```

- From GitHub Container Registry

```bash
docker pull ghcr.io/gmeligio/flutter:0.10.3-tf1.0.11-node16.15.0-alpine3.15
```

- From AWS ECR Public

```bash
docker pull public.ecr.aws/gmeligio/flutter:3.7.1-sdk33-ndk25
```
