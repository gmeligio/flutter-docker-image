# escape=`

FROM mcr.microsoft.com/windows/servercore:ltsc2025@sha256:39fa6d04598fff134c079d3547efd9726dd967e540a76f24e5181dbdea4780d0 as flutter

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

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


# The user ContainerAdministrator must be used because is the one that has permissions to install with vs_BuildTools
USER ContainerAdministrator
# Download the Build Tools bootstrapper
# See https://learn.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2022
RUN Invoke-WebRequest -Uri https://aka.ms/vs/17/release/vs_buildtools.exe -OutFile vs_BuildTools.exe; `
    Start-Process vs_BuildTools.exe -ArgumentList '--quiet --wait --norestart --nocache `
    --add Microsoft.VisualStudio.Component.VC.CMake.Project `
    --add Microsoft.VisualStudio.Component.Windows11SDK.22621 `
    --add Microsoft.VisualStudio.Workload.VCTools' `
    -Wait; `
    Remove-Item vs_BuildTools.exe;
USER ContainerUser

WORKDIR "$USERPROFILE/build_app"
RUN flutter build windows;

WORKDIR "$USERPROFILE"
COPY ./script/docker_windows_entrypoint.ps1 "docker_entrypoint.ps1"

ENTRYPOINT "C:\Users\ContainerUser\docker_entrypoint.ps1"

RUN Remove-Item -Recurse build_app;
