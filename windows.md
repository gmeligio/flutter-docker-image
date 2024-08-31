# Windows

## Swich between Linux and Windows containers

& $Env:ProgramFiles\Docker\Docker\DockerCli.exe -SwitchDaemon


## TODO

1. Check how it can be run in Github actions.
1. Check how it can be run in Gitlab CI/CD.
1. Test where is installed.
1. Test that path to powershell.exe exists.
1. Test with a snapshot of flutter config to determine if new feature flags should be enabled or disabled.
1. Check [Windows installation requirements for Flutter](https://docs.flutter.dev/get-started/install/windows/desktop)
1. Add docs explaining to use `$VerbosePreference = 'Continue';` in the SHELL to debug unexpected pwsh problems.

## Contribute flutter upstream

1. Remove `WHERE` in bin\internal\shared.bat and use instead:

    ```batch
    pwsh.exe -Command "exit" >nul 2>&1 && (
            SET powershell_executable=pwsh.exe
        ) || powershell.exe -Command "exit" >nul 2>&1 && (
            SET powershell_executable=PowerShell.exe
        ) || (
            ECHO Error: PowerShell executable not found.                        1>&2
            ECHO        Either pwsh.exe or PowerShell.exe must be in your PATH. 1>&2
            EXIT 1
        )
    ```

1. Find if the executable should be pwsh or powershell and put it in a service to remove the hardcoded "powershell" in multiple places, like in:

    - dev\devicelab\lib\framework\running_processes.dart
    - packages\flutter_tools\lib\src\windows\windows_version_validator.dart

## Steps to reproduce in Docker

1. Enable Windows Developer Settings to solve error:

    >Building with plugins requires symlink support.
    >
    >Please enable Developer Mode in your system settings. Run
    > start ms-settings:developers
    >to open settings.

    ```powershell
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"
    ```

1. For CI/CD

    1. Docker version must be pinned in Github workflow to avoid breaking changes: with escaping `\"` syntax inside RUN directive, etc.

    1. Packaging tool in Windows: <https://pub.dev/packages/msix> . It uses the executables:

        - [makeappx.exe](https://learn.microsoft.com/en-us/windows/win32/appxpkg/make-appx-package--makeappx-exe-)
        - [makepri.exe](https://learn.microsoft.com/en-us/windows/uwp/app-resources/makepri-exe-command-options)
        - [signtool.exe](https://learn.microsoft.com/en-us/dotnet/framework/tools/signtool-exe)

    1. Install msstore CLI.


    1. Install the [Windows App Certification Kit](https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-app-certification-kit) or the [Windows SDK that already includes it](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/)

## References

- [How environment variables work on Windows containers?](https://blog.sixeyed.com/windows-weekly-dockerfile-14-environment-variables/)
- [Windows deployment in Flutter](https://docs.flutter.dev/deployment/windows)
