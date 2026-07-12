BeforeAll {
    $script:manifest = Get-Content -Raw "config\version.json" | ConvertFrom-Json
}

Describe "Flutter version" {
    It "Should match the version in config/version.json" {
        $expectedVersion = $script:manifest.flutter.version

        $firstLine = flutter --version 2>&1 | Select-Object -First 1
        $firstLine -match 'Flutter (\S+)' | Out-Null
        $actualVersion = $Matches[1]

        $actualVersion | Should -Be $expectedVersion -Because "flutter --version reported '$actualVersion' but config/version.json specifies '$expectedVersion'"
    }
}

Describe "Flutter doctor" {
    BeforeAll {
        # Flutter doctor on Windows uses U+221A (SQUARE ROOT) for pass and ASCII X for fail.
        # On other platforms it uses U+2713/U+2717. Keep this source pure ASCII so Windows
        # PowerShell 5.x does not choke on the file encoding.
        $script:passMarkers = @([char]0x221A, [char]0x2713, [char]0x2714)
        $script:failMarkers = @('X', 'x', [char]0x2717, [char]0x2718)
        $script:doctorOutput = flutter doctor 2>&1
    }

    It "Should report a healthy Windows toolchain with no unexpected errors" {
        $skippedPlatforms = @('Android', 'iOS', 'macOS', 'Linux', 'Web', 'Chrome')
        $failures = @()
        $expectedMark = "[" + [char]0x221A + "]"

        foreach ($line in $script:doctorOutput) {
            if ($line -match '^\[(.)\] (.+)$') {
                $marker = $Matches[1]
                $header = $Matches[2]

                $skip = $false
                foreach ($platform in $skippedPlatforms) {
                    if ($header -like "$platform*") { $skip = $true; break }
                }
                if ($skip) { continue }

                $isPass = $script:passMarkers -contains $marker
                $isFail = $script:failMarkers -contains $marker

                if ($header -like 'Windows Version*' -or $header -like 'Visual Studio*') {
                    if (-not $isPass) {
                        $failures += "[$marker] $header (expected $expectedMark)"
                    }
                } elseif ($isFail) {
                    $failures += "[$marker] $header"
                }
            }
        }

        $failures | Should -BeNullOrEmpty -Because ($failures -join '; ')
    }
}

Describe "Git version" {
    It "Should match windows.git.version in config/version.json" {
        $expectedVersion = $script:manifest.windows.git.version

        $firstLine = git --version 2>&1 | Select-Object -First 1
        $firstLine -match 'git version (\d+\.\d+\.\d+)' | Out-Null
        $actualVersion = $Matches[1]

        $actualVersion | Should -Be $expectedVersion -Because "git --version reported '$actualVersion' but config/version.json specifies '$expectedVersion'"
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
            $expectedVersion = $script:manifest.windows.vsBuildTools.cmakeProject.version
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.VC.CMake.Project
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.VC.CMake.Project,version=$expectedVersion*"
        }

        It "Windows11SDK version matches" {
            $expectedBuild = $script:manifest.windows.vsBuildTools.windows11Sdk.build
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.Windows11SDK
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.Windows11SDK.$expectedBuild,version=*"
        }

        It "VCTools version matches" {
            $expectedVersion = $script:manifest.windows.vsBuildTools.vcTools.version
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Workload.NativeDesktop
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Workload.NativeDesktop,version=$expectedVersion*"
        }
    }
}
 