Describe "Flutter version" {
    It "Should match the version in config/version.json" {
        $manifest = Get-Content "config\version.json" | ConvertFrom-Json
        $expectedVersion = $manifest.flutter.version

        $firstLine = flutter --version 2>&1 | Select-Object -First 1
        $firstLine -match 'Flutter (\S+)' | Out-Null
        $actualVersion = $Matches[1]

        $actualVersion | Should -Be $expectedVersion -Because "flutter --version reported '$actualVersion' but config/version.json specifies '$expectedVersion'"
    }
}

Describe "Flutter doctor" {
    BeforeAll {
        $script:doctorOutput = flutter doctor 2>&1
    }

    It "Should report a healthy Windows toolchain with no unexpected errors" {
        $skippedPlatforms = @('Android', 'iOS', 'macOS', 'Linux', 'Web', 'Chrome')
        $failures = @()

        foreach ($line in $script:doctorOutput) {
            if ($line -match '^\[(.)\] (.+)$') {
                $marker = $Matches[1]
                $header = $Matches[2]

                $skip = $false
                foreach ($platform in $skippedPlatforms) {
                    if ($header -like "$platform*") { $skip = $true; break }
                }
                if ($skip) { continue }

                $isPass = ($marker -eq '✓') -or ($marker -eq '✔')
                $isFail = ($marker -eq '✗') -or ($marker -eq '✘') -or ($marker -eq 'x') -or ($marker -eq 'X')

                if ($header -like 'Windows Version*' -or $header -like 'Visual Studio*') {
                    if (-not $isPass) {
                        $failures += "[$marker] $header (expected [✓])"
                    }
                } elseif ($isFail) {
                    $failures += "[$marker] $header"
                }
            }
        }

        $failures | Should -BeNullOrEmpty -Because ($failures -join '; ')
    }
}

Describe "Windows file structure tests" {
    It "Should have specific file content in dart telemetry config" {
        "$env:APPDATA\.dart-tool\dart-flutter-telemetry.config" | Should -FileContentMatchExactly "reporting=0"
    }

    Context "VisualStudio components" {
        BeforeAll {
            $visualStudioPackages = (Get-ChildItem $env:ProgramData\Microsoft\VisualStudio\Packages).Name
        }    

        It "CMake version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.VC.CMake.Project
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.VC.CMake.Project,version=*"
        }

        It "Windows11SDK version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.Windows11SDK
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.Windows11SDK.22621,version=*"
        }

        It "VCTools version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Workload.VCTools
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Workload.VCTools,version=*"
        }
    }
}
 