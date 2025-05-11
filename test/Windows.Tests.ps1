Describe "Windows file structure tests" {
    It "Should have specific file content in config.txt" {
        "$env:APPDATA\.dart-tool\dart-flutter-telemetry.config" | Should -FileContentMatchExactly "reporting=0"
    }

    Context "VisualStudio components" {
        BeforeAll {
            $visualStudioPackages = (Get-ChildItem $env:ProgramData\Microsoft\VisualStudio\Packages).Name
        }    

        It "CMake version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.VC.CMake.Project
            $directoryName | Should -BeExactly "Microsoft.VisualStudio.Component.VC.CMake.Project,version=17.13.35710.127"
        }

        It "Windows11SDK version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.Windows11SDK
            $directoryName | Should -BeExactly "Microsoft.VisualStudio.Component.Windows11SDK.22621,version=17.13.35710.127"
        }

        It "VCTools version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Workload.VCTools
            $directoryName | Should -BeExactly "Microsoft.VisualStudio.Workload.VCTools,version=17.13.35710.127"
        }
    }
}
