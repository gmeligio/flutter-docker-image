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

# Building a Windows app proves the VS toolchain (MSVC compiler + Windows SDK + CMake)
# Flutter requires is installed and detectable. This mirrors the android (`gradlew
# bundleRelease`) and web (`flutter build web`) suites, which make a real build their
# primary gate. Without it, a missing or incomplete VS component set only surfaces as
# a cryptic "Unable to find suitable Visual Studio toolchain" at image-build time
# instead of a named test failure here.
Describe "Flutter Windows build" {
    It "Should build a Windows app with the installed toolchain" {
        flutter create build_smoke_test 2>&1 | Out-Null
        Push-Location build_smoke_test
        try {
            flutter build windows 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "flutter build windows must succeed — it proves the VS toolchain (Workload.NativeDesktop + VC.Tools.x86.x64 compiler + Windows11SDK + CMake) Flutter requires is correctly installed"
        }
        finally {
            Pop-Location
            Remove-Item -Recurse -Force build_smoke_test -ErrorAction SilentlyContinue
        }
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

        It "Windows10SDK version matches" {
            $expectedBuild = $script:manifest.windows.vsBuildTools.windows10Sdk.build
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.Windows10SDK
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.Windows10SDK.$expectedBuild,version=*"
        }

        It "VCTools version matches" {
            $expectedVersion = $script:manifest.windows.vsBuildTools.vcTools.version
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.VC.Tools.x86.x64
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.VC.Tools.x86.x64,version=$expectedVersion*"
        }

        It "NativeDesktop workload version matches" {
            $expectedVersion = $script:manifest.windows.vsBuildTools.nativeDesktop.version
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Workload.NativeDesktop
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Workload.NativeDesktop,version=$expectedVersion*"
        }
    }
}
 