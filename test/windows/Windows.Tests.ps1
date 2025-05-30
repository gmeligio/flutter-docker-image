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
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.VC.CMake.Project,versiona*"
        }

        It "Windows11SDK version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Component.Windows11SDK
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Component.Windows11SDK.22621,version*"
        }

        It "VCTools version matches" {
            $directoryName = $visualStudioPackages | Select-String -CaseSensitive Microsoft.VisualStudio.Workload.VCTools
            $directoryName | Should -BeLikeExactly "Microsoft.VisualStudio.Workload.VCTools,version*"
        }
    }
}
 