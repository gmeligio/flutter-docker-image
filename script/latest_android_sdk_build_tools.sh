sdkmanager --list | grep 'build-tools' | awk '{print $1}' | grep -oP 'build-tools;\d+\.\d+\.\d+$' | tail -1
