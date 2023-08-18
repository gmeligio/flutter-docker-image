curl -s https://developer.android.com/studio/ | grep -o 'tools-[0-9]\{14\}' | head -1 | grep -o '[0-9]\{14\}'

# Get the latest URL of the Android SDK command line tools
command_line_tools_url="$(curl -s https://developer.android.com/studio/ | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]\+_latest.zip')"

version=$($command_line_tools_url | grep -o '[0-9]\+')
