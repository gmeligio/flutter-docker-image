#!/usr/bin/env sh

# Path to the JSON and YAML files
version_file_path="./config/version.json"
test_file_path="./test/android.yml"

# Extracting the version value from the version.json file
android_cmdline_tools_version=$(yq -oy '.android.cmdlineTools.version' "$version_file_path")
android_cmdline_tools_test_expected_content="Pkg.Revision=$android_cmdline_tools_version
Pkg.Path=cmdline-tools;$android_cmdline_tools_version
Pkg.Desc=Android SDK Command-line Tools"

# Check if the version value is not empty
if [ -z "$android_cmdline_tools_version" ]; then
    echo "Error: Version not found in $version_file_path"
    exit 1
fi

# Update the YAML file using yq
# Replace 'path.to.version' with the actual path to the version field in the YAML file
yq -i ".fileContentTests[0].name = \"Android SDK Command-line Tools is version $android_cmdline_tools_version\" | .fileContentTests[0].expectedContents = \"$android_cmdline_tools_test_expected_content\"" "$test_file_path"

# Verify the update
echo "Updated $test_file_path with android_cmdline_tools_version: $android_cmdline_tools_version"
