# escape=`

FROM mcr.microsoft.com/powershell:lts-nanoserver-ltsc2022 as flutter

# USER flutter:flutter
# WORKDIR "$HOME"

SHELL [ "pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';" ]

ARG git_version=2.46.0
ARG git_installation_path="C:\Program Files\Git"

# TODO: Find a way to pass $env:USERPROFILE instead of hardcoding C:\Users\ContainerUser. It's hardcoded because  environment variables in Windows container works by setting for the Machine scope and that will have $env:USERPROFILE as C:\Users\ContainerAdministrator instead.
ENV USERPROFILE="C:\Users\ContainerUser"
ENV SDK_ROOT="${USERPROFILE}\sdks"
ENV FLUTTER_ROOT="${SDK_ROOT}\flutter"

WORKDIR "$USERPROFILE"

# where is required by Flutter but it's not available in the windows/nanoserver image
COPY --from=mcr.microsoft.com/windows/servercore:ltsc2022 C:\Windows\System32\where.exe C:\Windows\System32\where.exe

# Install Git that is required by Flutter
# RUN $installer = \"Git-${env:git_version}-64-bit.exe\";`
# $url = \"https://github.com/git-for-windows/git/releases/download/v${env:git_version}.windows.1/${installer}\"; `
# Start-Process -Wait -NoNewWindow "$installer" -ArgumentList '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NORESTART /NOCANCEL /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /SAVEINF=git.inf';
# Write-Host "$url"; `
RUN $installer = \"MinGit-${env:git_version}-busybox-64-bit.zip\"; `
    $url = \"https://github.com/git-for-windows/git/releases/download/v${env:git_version}.windows.1/${installer}\"; `
    Invoke-WebRequest -Uri "$url" -OutFile "$installer"; `
    Expand-Archive -Path "$installer" -DestinationPath "$env:git_installation_path"; `
    Remove-Item -Path "$installer"; 

# The user ContainerAdministrator must be used is the one that has permissions to set the system PATH
USER ContainerAdministrator

RUN [Environment]::SetEnvironmentVariable('Path', \"${env:Path};${env:git_installation_path}\cmd;${env:git_installation_path}\usr\bin;${env:FLUTTER_ROOT}\bin;${env:FLUTTER_ROOT}\bin\cache\dart-sdk\bin;\", 'Machine');

# The PATH variable will be updated in the next shell session, so the RUN command that sets the PATH needs to be separated from the one that uses it
# hadolint ignore=DL3059
RUN $env:GIT_CONFIG_NOSYSTEM=1; git config --system --unset-all include.path;

# Switch to the non-admin user when the admi user is not needed anymore
USER ContainerUser

# MinGit has a circular reference in its global configuration, which causes git to crash
# See https://github.com/git-for-windows/git/issues/2387#issuecomment-679367609

ARG flutter_version

RUN git clone --depth 1 --branch "$env:flutter_version" https://github.com/flutter/flutter "$env:FLUTTER_ROOT"; `
    flutter --version;


# dart --disable-analytics; `
# flutter config --no-analytics; `
# flutter config --no-enable-android; `
# flutter config --no-enable-web; `
# flutter config --no-enable-linux-desktop; `
# flutter config --no-enable-windows-desktop; `
# flutter config --no-enable-fuchsia; `
# flutter config --no-enable-custom-devices; `
# flutter config --no-enable-ios; `
# flutter config --no-enable-macos-desktop; `
# flutter doctor;

## && chown -R flutter:flutter "$FLUTTER_ROOT" `