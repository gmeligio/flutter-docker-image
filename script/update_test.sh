#!/usr/bin/env sh

# Path to the JSON and YAML files
version_file_path="./config/version.json"
test_file_path="./test/android.yml"
temp_file_path="./test/temp.yml"

# Extracting the version value from the version.json file
android_cmdline_tools_version=$(cue eval -e 'android.cmdlineTools.version' "$version_file_path" | tr -d '"')
android_cmdline_tools_test_expected_content="Pkg.Revision=$android_cmdline_tools_version
Pkg.Path=cmdline-tools;$android_cmdline_tools_version
Pkg.Desc=Android SDK Command-line Tools"

# Check if the version value is not empty
if [ -z "$android_cmdline_tools_version" ]; then
    echo "Error: Version not found in $version_file_path"
    exit 1
fi


# Update the version YAML file using cue
cue export config/android.cue -l input: ./test/android.yml -t android_cmdline_tools_version="$android_cmdline_tools_version" -t android_cmdline_tools_test_expected_content="$android_cmdline_tools_test_expected_content" -e output --out yaml >"$temp_file_path"
mv "$temp_file_path" "$test_file_path"

# Write progress
echo "Updated $test_file_path with android_cmdline_tools_version: $android_cmdline_tools_version"
