$analytic_tools_str = "Dart, Flutter and Fastlane"

if ($env:ENABLE_ANALYTICS -eq "true") {
    Write-Output "Received 'ENABLE_ANALYTICS=true'.`nEnabling analytics for $analytic_tools_str."

    dart --enable-analytics
    flutter config --analytics

    if (Test-Path env:FASTLANE_OPT_OUT_USAGE) {
        Remove-Item env:FASTLANE_OPT_OUT_USAGE
    }
}
else {
    dart --disable-analytics
    flutter --disable-analytics
    $env:POWERSHELL_TELEMETRY_OPTOUT = 1
    $env:FASTLANE_OPT_OUT_USAGE = "YES"
    # TODO: $env:COCOAPODS_DISABLE_STATS = 1
}

if ($args.length -gt 0) {
    Invoke-Expression "$args"
}
else {
    powershell
}
