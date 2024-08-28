# Windows

## Swich between Linux and Windows containers

& $Env:ProgramFiles\Docker\Docker\DockerCli.exe -SwitchDaemon

## Steps to reproduce in Docker

1. Check requirements in <https://docs.flutter.dev/get-started/install/windows/desktop>

1. Install the Flutter requirements: [Powershell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4#installing-the-zip-package)

1. Enable Windows Developer Settings to solve error:

>Building with plugins requires symlink support.
>
>Please enable Developer Mode in your system settings. Run
> start ms-settings:developers
>to open settings.

```powershell
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"
```

1. Support toosl:

    - <https://pub.dev/packages/msix>