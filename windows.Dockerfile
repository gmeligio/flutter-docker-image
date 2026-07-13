# escape=`

FROM mcr.microsoft.com/windows/servercore:ltsc2025@sha256:83374b6927f7945bb0933d03f158f84b03182017e2694fa23aedd24ea51434e4 as flutter

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG git_version
ARG git_installation_path="C:\Program Files\Git"

# TODO: Find a way to pass $env:USERPROFILE instead of hardcoding C:\Users\ContainerUser. It's hardcoded because  environment variables in Windows container works by setting for the Machine scope and that will have $env:USERPROFILE as C:\Users\ContainerAdministrator instead.
ENV USERPROFILE="C:\Users\ContainerUser"
ENV SDK_ROOT="${USERPROFILE}\sdks"
ENV FLUTTER_ROOT="${SDK_ROOT}\flutter"
# Set FLUTTER_GIT_URL to fix warning: "Upstream repository unknown source is not a standard remote. Set environment variable "FLUTTER_GIT_URL" to unknown source to dismiss this error."
ENV FLUTTER_GIT_URL="unknown source"

WORKDIR "$USERPROFILE"

# Install Git because is required by Flutter
RUN $installer = \"MinGit-${env:git_version}-busybox-64-bit.zip\"; `
    $url = \"https://github.com/git-for-windows/git/releases/download/v${env:git_version}.windows.1/${installer}\"; `
    Invoke-WebRequest -Uri "$url" -OutFile "$installer"; `
    Expand-Archive -Path "$installer" -DestinationPath "$env:git_installation_path"; `
    Remove-Item -Path "$installer"; 

# The user ContainerAdministrator must be used because is the one that has permissions to set the system PATH
USER ContainerAdministrator

# The PATH variable will be updated in the next shell session, so the RUN command that sets the PATH needs to be separated from the one that uses it
RUN [Environment]::SetEnvironmentVariable('PATH', \"${env:PATH};${env:git_installation_path}\cmd;${env:git_installation_path}\usr\bin;${env:FLUTTER_ROOT}\bin;${env:FLUTTER_ROOT}\bin\cache\dart-sdk\bin;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\msbuild\current\bin\", 'Machine');

# MinGit has a circular reference in its global configuration, which causes git to crash
# See https://github.com/git-for-windows/git/issues/2387#issuecomment-679367609
# hadolint ignore=DL3059
RUN $env:GIT_CONFIG_NOSYSTEM=1; git config --system --unset-all include.path;

# Switch to the non-admin user when the admin user is not needed anymore
USER ContainerUser

ARG flutter_version

RUN git clone `
    --depth 1 `
    --branch "$env:flutter_version" `
    https://github.com/flutter/flutter `
    "$env:FLUTTER_ROOT"; `
    # To fix fatal: detected dubious ownership in repository at 'C:/Users/ContainerUser/sdks/flutter/.git' owned by BUILTIN/Administrators but the current user is: User Manager/ContainerUser
    git config --global --add safe.directory "$env:FLUTTER_ROOT"; `
    flutter --version; `
    dart --disable-analytics; `
    flutter config `
    --no-cli-animations `
    --no-analytics `
    --no-enable-android `
    --no-enable-web `
    --no-enable-linux-desktop `
    --enable-windows-desktop `
    --no-enable-fuchsia `
    --no-enable-custom-devices `
    --no-enable-ios `
    --no-enable-macos-desktop; `
    flutter doctor --verbose; `
    flutter precache --windows; `
    flutter create build_app;


ARG vs_cmake_version
ARG vs_win11sdk_build
ARG vs_vctools_version

# The user ContainerAdministrator must be used because is the one that has permissions to install with vs_BuildTools
USER ContainerAdministrator
# Download the Build Tools bootstrapper
# See https://learn.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2022
RUN Invoke-WebRequest -Uri https://aka.ms/vs/17/release/vs_buildtools.exe -OutFile vs_BuildTools.exe; `
    # Flutter's toolchain detection (vswhere -requires) accepts either the NativeDesktop
    # or VCTools workload, but on the Build Tools SKU only Workload.VCTools registers as
    # satisfied — NativeDesktop returns NO MATCH from vswhere even when installed (verified
    # on PR #518). VCTools pulls the MSVC compiler, CMake, and the Windows 10/11 SDKs that
    # `flutter build windows` needs; the explicit CMake + Win11SDK adds pin those versions.
    $p = Start-Process vs_BuildTools.exe -ArgumentList \"--quiet --wait --norestart --nocache `
    --add Microsoft.VisualStudio.Component.VC.CMake.Project `
    --add Microsoft.VisualStudio.Component.Windows11SDK.${env:vs_win11sdk_build} `
    --add Microsoft.VisualStudio.Workload.VCTools\" `
    -Wait -PassThru; `
    # Exit code 3010 = success but reboot required (fine in a container). Any other
    # non-zero means the install did not complete — fail loudly instead of shipping a
    # partial VS install that Flutter's vswhere check will later reject.
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { `
      Write-Host \"vs_buildtools.exe failed with exit code $($p.ExitCode); dumping logs:\"; `
      Get-Content -Path \"$env:TEMP\dd_*.log\" -ErrorAction SilentlyContinue; `
      exit $p.ExitCode; `
    } `
    Remove-Item vs_BuildTools.exe; `
    # Remove VS installer logs in this same layer; a later cleanup layer cannot shrink it.
    Remove-Item -Path \"$env:TEMP\dd_*\" -Recurse -Force -ErrorAction SilentlyContinue;
USER ContainerUser

# Warm up + validate the toolchain at build time, then delete the throwaway output
# in the SAME layer so the ~99 MB build_app never commits to a persistent layer.
# On failure, dump the toolchain state (doctor + installed VS packages) so a broken
# component set is diagnosable from the build log, not guessed from install timing.
WORKDIR "$USERPROFILE/build_app"
RUN flutter build windows; `
    if ($LASTEXITCODE -ne 0) { `
      $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'; `
      Write-Host '===== flutter doctor -v ====='; `
      flutter doctor -v; `
      # Reproduce Flutter's EXACT vswhere query (visual_studio.dart): the -requires AND of the `
      # workload + VC.Tools + CMake decides `meetsRequirements`; the install's own isComplete `
      # decides the rest of `isUsable`. Dumping both tells us which gate actually fails. `
      Write-Host '===== vswhere -requires per-ID (isolate which requirement fails meetsRequirements) ====='; `
      foreach ($req in @('Microsoft.VisualStudio.Workload.NativeDesktop', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', 'Microsoft.VisualStudio.Component.VC.CMake.Project')) { `
        $hit = & $vswhere -format value -property installationVersion -products * -utf8 -latest -version 16 -requires $req; `
        Write-Host \"  requires $req => $(if ($hit) { 'MATCH ' + $hit } else { 'NO MATCH' })\"; `
      } `
      Write-Host '===== vswhere -requiresAny fallback + all installed packages under the instance ====='; `
      & $vswhere -format value -property installationVersion -products * -utf8 -latest -version 16 `
        -requires Microsoft.VisualStudio.Workload.NativeDesktop Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.CMake.Project; `
      Write-Host '===== vswhere -all (isComplete / isLaunchable / isRebootRequired / installationVersion) ====='; `
      & $vswhere -all -prerelease -products * -format json -utf8 `
        | ConvertFrom-Json | ForEach-Object { $_ | Select-Object displayName, installationVersion, isComplete, isLaunchable, isRebootRequired, isPrerelease | Format-List }; `
      Write-Host '===== MSVC toolset dirs (Flutter reads VC\\Tools\\MSVC) ====='; `
      Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name; `
      exit 1; `
    } `
    Set-Location "$env:USERPROFILE"; `
    Remove-Item -Recurse -Force build_app;

WORKDIR "$USERPROFILE"
COPY ./script/docker_windows_entrypoint.ps1 "docker_entrypoint.ps1"

# hadolint ignore=DL3025
ENTRYPOINT "C:\Users\ContainerUser\docker_entrypoint.ps1"

#-----------------------------------------------
#-----------------------------------------------
#-----------------------------------------------

FROM flutter as test

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# TODO: Find a way to pass $env:USERPROFILE instead of hardcoding C:\Users\ContainerUser. It's hardcoded because  environment variables in Windows container works by setting for the Machine scope and that will have $env:USERPROFILE as C:\Users\ContainerAdministrator instead.
ENV USERPROFILE="C:\Users\ContainerUser"

WORKDIR "$USERPROFILE"

# Install Pester
COPY ./script/InstallPester.ps1 ".\InstallPester.ps1"

# Administrator rights are required to install modules in 'C:\Program Files\WindowsPowerShell\Modules'
USER ContainerAdministrator
RUN ".\InstallPester.ps1"; `
    Remove-Item ".\InstallPester.ps1"; `
    Import-Module Pester;
USER ContainerUser

# Run the tests
COPY ./config/version.json ".\config\version.json"
COPY ./test/windows/Windows.Tests.ps1 ".\test\Windows.Tests.ps1"
COPY ./script/RunPester.ps1 ".\script\RunPester.ps1"

# Reset the inherited shell-form ENTRYPOINT from the flutter stage. The test image runs Pester,
# not the analytics-toggle entrypoint, and shell-form ENTRYPOINT prevents CMD args from being
# appended cleanly (Docker emits "Shell-form ENTRYPOINT and exec-form CMD may have unexpected
# results" otherwise).
ENTRYPOINT ["powershell", "-NoLogo", "-NoProfile", "-File"]
CMD [".\\script\\RunPester.ps1"]
