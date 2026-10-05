#!/usr/bin/env sh
# TODO: Update all versions used in android.yml from version.json, like NDK, CMake, etc.

# Path to the JSON and YAML files
version_file_path="./config/version.json"
test_file_path="./test/android.yml"
temp_file_path="./test/temp.yml"

# Extracting the version value from the version.json file
android_ndk_version=$(cue eval -e 'android.ndk.version' "$version_file_path" | tr -d '"')
android_sdk_build_tools_version=$(cue eval -e 'android.buildTools.version' "$version_file_path" | tr -d '"')
android_java_version=$(cue eval -e 'android.java.version' "$version_file_path" | tr -d '"')

# Update the version YAML file using cue
cue export config/android.cue -l input: ./test/android.yml -t android_ndk_version="$android_ndk_version" -t android_sdk_build_tools_version="$android_sdk_build_tools_version" -t android_java_version="$android_java_version" -e output --out yaml >"$temp_file_path"
mv "$temp_file_path" "$test_file_path"

# Write progress
echo "Updated $test_file_path with android_ndk_version=$android_ndk_version, android_sdk_build_tools_version=$android_sdk_build_tools_version, android_java_version=$android_java_version"
