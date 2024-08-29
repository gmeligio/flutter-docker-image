# escape=`

FROM mcr.microsoft.com/powershell:lts-nanoserver-ltsc2022 as flutter

# USER flutter:flutter
# WORKDIR "$HOME"

SHELL [ "pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';" ]

ARG GIT_VERSION=2.46.0
ARG GIT_INSTALLATION_PATH="C:\Program Files\Git"

# Install Git
RUN $installer = \"MinGit-${env:GIT_VERSION}-busybox-64-bit.zip\"; `
    # RUN $installer = \"Git-${env:GIT_VERSION}-64-bit.exe\";`
    # $url = \"https://github.com/git-for-windows/git/releases/download/v${env:GIT_VERSION}.windows.1/${installer}\"; `
    $url = \"https://github.com/git-for-windows/git/releases/download/v${env:GIT_VERSION}.windows.1/${installer}\"; `
    # Write-Host "$url"; `
    Invoke-WebRequest -Uri "$url" -OutFile "$installer"; `
    # Start-Process -Wait -NoNewWindow "$installer" -ArgumentList '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NORESTART /NOCANCEL /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /SAVEINF=git.inf';
    Expand-Archive -Path "$installer" -DestinationPath "$env:GIT_INSTALLATION_PATH"; `
    Remove-Item -Path "$installer";

# In order to set system PATH, ContainerAdministrator must be used
USER ContainerAdministrator
RUN [Environment]::SetEnvironmentVariable('Path', \"${env:GIT_INSTALLATION_PATH}\cmd;${env:GIT_INSTALLATION_PATH}\usr\bin;${env:Path};\", 'Machine');
USER ContainerUser

# MinGit has a circular reference in its global configuration, which causes git to crash
# See https://github.com/git-for-windows/git/issues/2387#issuecomment-679367609
RUN $env:GIT_CONFIG_NOSYSTEM=1; git config --system --unset-all include.path


# $installerPath = Join-Path -Path $env:ProgramFiles -ChildPath "Git"; `
# Download the Git installer
# Write-Output $gitInstaller; `
# Write-Output $gitUrl; `
# Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller;
# # Decompress
# Expand-Archive -Path $gitInstaller -DestinationPath $installerPath; `
# # Clean up the installer file
# Remove-Item -Path $installerPath; `
# # Verify installation
# git --version


















# USER ContainerAdministrator

# SHELL [ "cmd", "/v", "/s", "/c" ]

# # Set variables first because ENV is not supported on Windows
# RUN setx /m PS_MAJOR_VERSION "7" `
#     && setx /m PS_INSTALL_PATH "%ProgramFiles%\PowerShell\%PS_MAJOR_VERSION%" `
#     && setx /m PS_VERSION "7.4.5" `
#     && setx /m PS_INSTALLER "PowerShell-%PS_VERSION%-win-x64.zip"

# RUN setx /m PATH "%PS_INSTALL_PATH%;%PATH%"

# RUN curl -L -o "%PS_INSTALLER%" "https://github.com/PowerShell/PowerShell/releases/download/v%PS_VERSION%/%PS_INSTALLER%" `
#     && mkdir "%PS_INSTALL_PATH%" `
#     && tar -xf "%PS_INSTALLER%" -C "%PS_INSTALL_PATH%" `
#     && del "%PS_INSTALLER%"


# ENV SDK_ROOT="$HOME/sdks"
# ENV FLUTTER_ROOT="$SDK_ROOT/flutter"
# ENV PATH="$PATH:$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin"

# ENV GIT_INSTALLER=MinGit-%GIT_VERSION%-busybox-64-bit.zip


# RUN setx /m GIT_VERSION 2.41.0 \
#     set GIT_INSTALLER=MinGit-%GIT_VERSION%-busybox-64-bit.zip \
#     setx /m GIT_INSTALLER "%GIT_INSTALLER%"

# RUN curl -L -o %GIT_INSTALLER% https://github.com/git-for-windows/git/releases/download/v%GIT_VERSION%.windows.1/%GIT_INSTALLER% && \
#     dir C: \
#     mkdir C:\git && \
#     tar -xf %GIT_INSTALLER% -C C:\git && \
#     del %GIT_INSTALLER%

# RUN setx PATH "C:\git\cmd;C:\git\usr\bin;%PATH%"
# ARG flutter_version

# RUN git clone \
#     --depth 1 \
#     --branch "$flutter_version" \
#     https://github.com/flutter/flutter.git \
#     "$FLUTTER_ROOT" \
#     # && chown -R flutter:flutter "$FLUTTER_ROOT" \
#     && flutter --version \
#     && dart --disable-analytics \
#     && flutter config --no-analytics \
#     && flutter config --no-enable-android \
#     && flutter config --no-enable-web \
#     && flutter config --no-enable-linux-desktop \
#     && flutter config --no-enable-windows-desktop \
#     && flutter config --no-enable-fuchsia \
#     && flutter config --no-enable-custom-devices \
#     && flutter config --no-enable-ios \
#     && flutter config --no-enable-macos-desktop \
#     && flutter doctor
