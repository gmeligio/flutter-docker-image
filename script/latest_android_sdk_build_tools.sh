sdkmanager --list | grep 'build-tools' | awk '{print $1}' | grep -oP 'build-tools;\d+\.\d+\.\d+$' | tail -1

# Get 36.0.0 from `build-tools;36.0.0:build-tools`
curl -s https://raw.githubusercontent.com/flutter/flutter/refs/tags/3.35.1/engine/src/flutter/tools/android_sdk/packages.txt | grep 'build-tools' | awk -F'[;:]' '{print $2}'