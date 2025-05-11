Describe "Windows file structure tests" {

    It "Should have C:\ProgramData directory" {
        "C:\ProgramData" | Should -Exist
    }

    It "Should have specific file content in config.txt" {
        $content = Get-Content "C:\path\to\config.txt"
        $content | Should -Match "expected value"
    }

    It "Should execute command and validate output" {
        $result = & ipconfig
        $result | Should -Match "IPv4 Address"
    }
}
