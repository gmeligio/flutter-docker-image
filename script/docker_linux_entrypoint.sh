#!/usr/bin/env bash

analytic_tools_str="Dart, Flutter and Fastlane"

if [ "$ENABLE_ANALYTICS" = "true" ]; then
    echo -e "Received 'ENABLE_ANALYTICS=true'.\nEnabling analytics for $analytic_tools_str."

    dart --enable-analytics
    flutter config --analytics
    unset FASTLANE_OPT_OUT_USAGE

    # export COCOAPODS_DISABLE_STATS=1
fi

exec "$@"
