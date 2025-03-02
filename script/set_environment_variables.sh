#!/usr/bin/env bash

{
    echo "FLUTTER_VERSION=$(cue eval -e 'flutter.version' "$VERSION_MANIFEST" | tr -d '"')"

    echo "FASTLANE_VERSION=$(cue eval -e 'fastlane.version' "$VERSION_MANIFEST" | tr -d '"')"

    echo "ANDROID_BUILD_TOOLS_VERSION=$(cue eval -e 'android.buildTools.version' "$VERSION_MANIFEST" | tr -d '"')"

    echo "ANDROID_PLATFORM_VERSIONS=$(cue eval -e 'strings.Join([for p in android.platforms {"\(p.version)"}], " ")' "$VERSION_MANIFEST" | tr -d '"\n')"

    echo "ANDROID_NDK_VERSION=$(cue eval -e 'android.ndk.version' "$VERSION_MANIFEST" | tr -d '"')"

    echo "CMAKE_VERSION=$(cue eval -e 'android.cmake.version' "$VERSION_MANIFEST" | tr -d '"')"

    echo "IMAGE_REPOSITORY_PATH=$GITHUB_REPOSITORY_OWNER/$IMAGE_REPOSITORY_NAME"
} >>"$GITHUB_ENV"
