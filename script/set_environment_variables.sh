#!/usr/bin/env bash

IMAGE_REPOSITORY_PATH="$GITHUB_REPOSITORY_OWNER/$IMAGE_REPOSITORY_NAME"

{
    echo "FLUTTER_VERSION=$(jq -r '.flutter.version' "$VERSION_MANIFEST")"

    echo "FASTLANE_VERSION=$(jq -r '.fastlane.version' "$VERSION_MANIFEST")"

    echo "ANDROID_BUILD_TOOLS_VERSION=$(jq -r '.android.buildTools.version' "$VERSION_MANIFEST")"

    echo "ANDROID_PLATFORM_VERSIONS=$(jq -r '.android.platforms[].version' "$VERSION_MANIFEST" | tr '\n' ' ' | sed 's/ $//')"

    echo "ANDROID_NDK_VERSION=$(jq -r '.android.ndk.version' "$VERSION_MANIFEST")"

    echo "IMAGE_REPOSITORY_PATH=$IMAGE_REPOSITORY_PATH"
} >>"$GITHUB_ENV"
