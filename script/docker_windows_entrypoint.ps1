$analytic_tools_str = "Dart, Flutter and Fastlane"

if ($env:ENABLE_ANALYTICS -eq "true") {
    Write-Output "Received 'ENABLE_ANALYTICS=true'.`nEnabling analytics for $analytic_tools_str."

    dart --enable-analytics
    flutter config --analytics

    if (Test-Path env:FASTLANE_OPT_OUT_USAGE) {
        Remove-Item env:FASTLANE_OPT_OUT_USAGE
    }

    # $env:POWERSHELL_TELEMETRY_OPTOUT=1

    # $env:COCOAPODS_DISABLE_STATS = 1
}

if ($args.length -gt 0) {
    Invoke-Expression "$args"
}
else {
    # pwsh
    powershell
}
