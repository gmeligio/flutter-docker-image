# escape=`

# FROM mcr.microsoft.com/powershell:lts-7.2-nanoserver-ltsc2022@sha256:816b28df3ce39a36d6c6f696a4fd6f7823e09defb2af865f31501e868cb0e082 as flutter
FROM mcr.microsoft.com/windows/servercore:ltsc2022@sha256:b7b2e5b4c2414400c4eef13db747376e0f10ef8e15b8d0587ef5b953ad4e6d43 as flutter

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
# SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG git_version=2.46.0
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
RUN [Environment]::SetEnvironmentVariable('PATH', \"${env:PATH};${env:git_installation_path}\cmd;${env:git_installation_path}\usr\bin;${env:FLUTTER_ROOT}\bin;${env:FLUTTER_ROOT}\bin\cache\dart-sdk\bin;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\msbuild\current\bin\", 'Machine'); `
    # Download the Build Tools bootstrapper
    # See https://learn.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2022
    Invoke-WebRequest -Uri https://aka.ms/vs/17/release/vs_buildtools.exe -OutFile vs_BuildTools.exe; `
    Start-Process vs_BuildTools.exe -ArgumentList '--quiet --wait --norestart --nocache --includeRecommended `
    --add Microsoft.Component.MSBuild `
    --add Microsoft.VisualStudio.Workload.VCTools `
    --add Microsoft.VisualStudio.ComponentGroup.VC.Tools.142.x86.x64' -Wait; `
    Remove-Item vs_BuildTools.exe;

# MinGit has a circular reference in its global configuration, which causes git to crash
# See https://github.com/git-for-windows/git/issues/2387#issuecomment-679367609
# hadolint ignore=DL3059
RUN $env:GIT_CONFIG_NOSYSTEM=1; git config --system --unset-all include.path;

# Flutter uses a hardcoded powershell command for flutter doctor so powershell.exe needs to exist https://github.com/flutter/flutter/blob/3123d98132ba392025469d459846f7ccc44b6040/packages/flutter_tools/lib/src/windows/windows_version_validator.dart#L111    
# RUN $pwshInstallationPath = Split-Path -Parent (Get-Command pwsh).Source; `
#     New-Item -Force -ItemType SymbolicLink -Path "${pwshInstallationPath}\powershell.exe" -Target "${pwshInstallationPath}\pwsh.exe";

# Switch to the non-admin user when the admin user is not needed anymore
USER ContainerUser

# Copy the where executable because is required by Flutter but it's not available in the windows/nanoserver image
# COPY --from=mcr.microsoft.com/windows/servercore:ltsc2022 C:\Windows\System32\where.exe C:\Windows\System32\where.exe

ARG flutter_version

# RUN $env:GIT_CONFIG_NOSYSTEM=1; git config --system --unset-all include.path; `
RUN git clone `
    --depth 1 `
    --branch "$env:flutter_version" `
    https://github.com/flutter/flutter `
    "$env:FLUTTER_ROOT"; `
    flutter --version; `
    dart --disable-analytics; `
    flutter config `
    --no-cli-animations `
    --no-analytics `
    --no-enable-android `
    --no-enable-web `
    --no-enable-linux-desktop `
    --no-enable-windows-desktop `
    --no-enable-fuchsia `
    --no-enable-custom-devices `
    --no-enable-ios `
    --no-enable-macos-desktop; `
    flutter doctor;

# ## && chown -R flutter:flutter "$FLUTTER_ROOT" `

COPY ./script/docker_windows_entrypoint.ps1 "docker_entrypoint.ps1"

ENTRYPOINT "C:\Users\ContainerUser\docker_entrypoint.ps1"
