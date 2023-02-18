sdkmanager --list | grep 'ndk' | awk '{print $1}' | grep -oP 'ndk;\d+\.\d+\.\d+$' | tail -1
