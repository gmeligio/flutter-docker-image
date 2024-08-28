# escape=`

FROM mcr.microsoft.com/windows/nanoserver:ltsc2022 as flutter

# USER flutter:flutter
# WORKDIR "$HOME"

USER ContainerAdministrator

SHELL [ "cmd", "/v", "/s", "/c" ]

# Set variables first because ENV is not supported on Windows
RUN setx /m PS_MAJOR_VERSION "7" `
    && setx /m PS_VERSION "7.4.5" `
    && setx /m PS_INSTALLER "PowerShell-%PS_VERSION%-win-x64.zip" `
    && setx /m PS_INSTALL_PATH "%ProgramFiles%\PowerShell\%PS_MAJOR_VERSION%"

RUN curl -L -o "%PS_INSTALLER%" "https://github.com/PowerShell/PowerShell/releases/download/v%PS_VERSION%/%PS_INSTALLER%" `
    && mkdir "%PS_INSTALL_PATH%" `
    && tar -xf "%PS_INSTALLER%" -C "%PS_INSTALL_PATH%" `
    && del "%PS_INSTALLER%"

# RUN curl -SL --output dotnet.zip https://dotnetcli.blob.core.windows.net/dotnet/Sdk/%DOTNET_SDK_VERSION%/dotnet-sdk-%DOTNET_SDK_VERSION%-win-arm.zip `
#     && mkdir "%ProgramFiles%\dotnet" `
#     && tar -zxf dotnet.zip -C "%ProgramFiles%\dotnet" `
#     && del dotnet.zip

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
