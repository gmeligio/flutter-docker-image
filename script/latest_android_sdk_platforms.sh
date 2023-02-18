sdkmanager --list | grep 'platforms;android' | awk '{print $1}' | grep -oP '\d+$' | sort -n | tail -1
