<!--- This markdown file was auto-generated from "windows.mdx" -->

# Windows

## Swich between Linux and Windows containers

& $Env:ProgramFiles\\Docker\\Docker\\DockerCli.exe -SwitchDaemon

## TODO

1. Install tools

```powershell
   # # needed? No
#    --add Microsoft.Component.MSBuild' `
   # # needed? No
   # --add Microsoft.VisualStudio.Component.TestTools.BuildTools `
   # # needed? No
   # --add Microsoft.VisualStudio.Component.VC.ASAN `
   # # needed? no
   # # --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
RUN Invoke-WebRequest -Uri https://aka.ms/vs/17/release/vs_buildtools.exe -OutFile vs_BuildTools.exe; `
    Start-Process vs_BuildTools.exe -ArgumentList '--quiet --wait --norestart --nocache `
   # # needed? yes
   # --add Microsoft.VisualStudio.Component.VC.CMake.Project `
   # # needed? Yes
   # --add Microsoft.VisualStudio.Component.Windows11SDK.22621 `
   # # needed?
   # --add Microsoft.VisualStudio.Workload.VCTools' `
    -Wait; `
    Remove-Item vs_BuildTools.exe;

```

1. Read dependencies from [flutter\_tools](https://github.com/flutter/flutter/blob/master/packages/flutter%5Ftools/lib/src/windows/visual%5Fstudio.dart).
2. Check how it can be run in Github actions.
3. Check how it can be run in Gitlab CI/CD.
4. Test where is installed.
5. Test that path to powershell.exe exists.
6. Test with a snapshot of flutter config to determine if new feature flags should be enabled or disabled.
7. Test that Build Tools were installed in C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\msbuild\\current\\bin
8. Check [Windows installation requirements for Flutter](https://docs.flutter.dev/get-started/install/windows/desktop)
9. Add docs explaining to use `$VerbosePreference = 'Continue';` in the SHELL to debug unexpected pwsh problems.

## Open issue in windows Docker images repo

1. Some images can be pulled while others give error:  
```text  
Error response from daemon: Get "https://mcr.microsoft.com/v2/": read tcp [2a0c:5a84:e100:e501::a97c]:58039->[2603:1061:f:101::10]:443: wsarecv: An existing connection was forcibly closed by the remote host.  
```

Debug with `curl -A github165 -v https://mcr.microsoft.com/v2/powershell/manifests/lts-nanoserver-ltsc2022`

## Contribute flutter upstream

1. Remove `WHERE` in bin\\internal\\shared.bat and use instead:  
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
2. Find if the executable should be pwsh or powershell and put it in a service to remove the hardcoded "powershell" in multiple places, like in:  
   * dev\\devicelab\\lib\\framework\\running\_processes.dart  
   * packages\\flutter\_tools\\lib\\src\\windows\\windows\_version\_validator.dart

## Steps to reproduce in Docker

1. Enable Windows Developer Settings to solve error:  
```powershell  
# >Building with plugins requires symlink support.  
# >  
# >Please enable Developer Mode in your system settings. Run  
# > start ms-settings:developers  
# >to open settings.  
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"  
```
2. For CI/CD  
   1. Docker version must be pinned in Github workflow to avoid breaking changes: with escaping `\"` syntax inside RUN directive, etc.  
   2. Packaging tool in Windows: [msix](https://pub.dev/packages/msix) . It uses the executables:  
         * [makeappx.exe](https://learn.microsoft.com/en-us/windows/win32/appxpkg/make-appx-package--makeappx-exe-)  
         * [makepri.exe](https://learn.microsoft.com/en-us/windows/uwp/app-resources/makepri-exe-command-options)  
         * [signtool.exe](https://learn.microsoft.com/en-us/dotnet/framework/tools/signtool-exe)  
         * certificate  
                  * Make a note that --install-certificate should be "false" or configured because the certificate can't be installed as ContainerUser.  
         ```powershell  
         # OK  
         Import-PfxCertificate -FilePath "C:\Users\ContainerUser\AppData\Local\Pub\Cache\hosted\pub.dev\msix-3.16.8\lib\assets\test_certificate.pfx" -Password (ConvertTo-SecureString -AsPlainText -Force "1234") -CertStoreLocation Cert:\LocalMachine\Root  
         # Doesn't work  
         Import-PfxCertificate -FilePath "C:\Users\ContainerUser\AppData\Local\Pub\Cache\hosted\pub.dev\msix-3.16.8\lib\assets\test_certificate.pfx" -Password (ConvertTo-SecureString -AsPlainText -Force "1234")  
         ```  
   3. Install msstore CLI <https://github.com/microsoft/msstore-cli> It seems behind StoreBroker but it looks that it's going to be the primary and recommended way to publish to Microsoft Store  
         * According to the [msstore guide](https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/commands?pivots=msstoredevcli-installer-linux#installation), It will be needed to install Microsoft.NetCore.Component.Runtime.8.0 with vs\_BuildTools  
   4. From [github.com/tauu/flutter-windows-builder/Dockerfile](https://github.com/tauu/flutter-windows-builder/blob/main/Dockerfile) \=> install [github.com/microsoft/StoreBroker](https://github.com/microsoft/StoreBroker) This is currently the primary tool to publish to Microsoft Store  
         * Not installed right now  
   5. Install the [Windows App Certification Kit](https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-app-certification-kit) or the [Windows SDK that already includes it](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/)  
         * Installed currently by one of the workloads in vs\_BuildTools

## References

* [How environment variables work on Windows containers?](https://blog.sixeyed.com/windows-weekly-dockerfile-14-environment-variables/)
* [Windows deployment in Flutter](https://docs.flutter.dev/deployment/windows)
* [vs\_BuildTools workloads](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?view=vs-2022&preserve-view=true)
* Useful Dockerfile <https://git.openprivacy.ca/openprivacy/flutter-desktop/src/branch/main/windows/Dockerfile>