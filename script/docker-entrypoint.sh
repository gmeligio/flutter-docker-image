#!/bin/sh

analytic_tools_str="Dart and Flutter"

if [ "$ENABLE_ANALYTICS" = "true" ]; then
    echo "Received 'ENABLE_ANALYTICS=true'.\nEnabling analytics for $analytic_tools_str."
    dart --enable-analytics
    flutter config --analytics
else
    echo "Analytics are opt-in and disabled by default in $analytic_tools_str.\nTo enable analytics, pass the environment variable 'ENABLE_ANALYTICS=true' when starting the container."
fi

exec "$@"
