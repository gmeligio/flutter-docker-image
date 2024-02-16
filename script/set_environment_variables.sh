#!/usr/bin/env bash

IMAGE_REPOSITORY_PATH="$GITHUB_REPOSITORY_OWNER/$IMAGE_REPOSITORY_NAME"
CACHE_REPOSITORY_PATH="ghcr.io/$IMAGE_REPOSITORY_PATH"

{
    echo "FLUTTER_VERSION=$(jq -r '.flutter.version' "$VERSION_MANIFEST")"

    echo "FASTLANE_VERSION=$(jq -r '.fastlane.version' "$VERSION_MANIFEST")"

    echo "ANDROID_PLATFORM_VERSIONS=$(jq -r '.android.platforms[].version' "$VERSION_MANIFEST" | tr '\n' ' ' | sed 's/ $//')"

    echo "IMAGE_REPOSITORY_PATH=$IMAGE_REPOSITORY_PATH"

    echo "CACHE_REPOSITORY_PATH=$CACHE_REPOSITORY_PATH"
} >>"$GITHUB_ENV"
