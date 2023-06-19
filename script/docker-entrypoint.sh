#!/bin/sh

analytic_tools_str="Dart, Flutter and Fastlane"

if [ "$ENABLE_ANALYTICS" = "true" ]; then
    echo "Received 'ENABLE_ANALYTICS=true'.\nEnabling analytics for $analytic_tools_str."
    
    dart --enable-analytics
    flutter config --analytics
    unset FASTLANE_OPT_OUT_USAGE

    # export COCOAPODS_DISABLE_STATS=1
else
    echo "Analytics are opt-in and disabled by default in $analytic_tools_str.\nTo enable analytics, pass the environment variable 'ENABLE_ANALYTICS=true' when starting the container."
fi

exec "$@"
