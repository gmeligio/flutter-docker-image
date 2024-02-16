#!/usr/bin/env bash

IMAGE_REPOSITORY_PATH="${{ github.repository_owner }}/${{ env.IMAGE_REPOSITORY_NAME }}"
CACHE_REPOSITORY_PATH="ghcr.io/$IMAGE_REPOSITORY_PATH"

{
    echo "FLUTTER_VERSION=$(jq -r '.flutter.version' ${{ env.VERSION_MANIFEST }})"
    echo "FASTLANE_VERSION=$(jq -r '.fastlane.version' ${{ env.VERSION_MANIFEST }})"
    echo "ANDROID_PLATFORM_VERSIONS=$(jq -r '.android.platforms[].version' config/version.json)"
    echo "IMAGE_REPOSITORY_PATH=$IMAGE_REPOSITORY_PATH"
    echo "CACHE_REPOSITORY_PATH=$CACHE_REPOSITORY_PATH"
} >> "$GITHUB_ENV"