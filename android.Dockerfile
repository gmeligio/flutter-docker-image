FROM debian:12.10-slim@sha256:b1211f6d19afd012477bd34fdcabb6b663d680e0f4b0537da6e6b0fd057a3ec3 AS flutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV LANG=C.UTF-8

# renovate: release=bullseye depName=curl
ARG CURL_VERSION="7.88.1-10+deb12u12"
# renovate: release=bullseye depName=ca-certificates
ARG CA_CERTIFICATES_VERSION="20230311"
# renovate: release=bullseye depName=unzip
ARG UNZIP_VERSION="6.0-28"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl="$CURL_VERSION" \
    ca-certificates="$CA_CERTIFICATES_VERSION" \
    unzip="$UNZIP_VERSION" \
    && rm -rf /var/lib/apt/lists/*

# After finishing with root user, set the HOME folder for the non-root user
ENV HOME=/home/flutter

# The Github runner clones the repository with uid 1001 and gid 1001. This uid 1001 needs to be the set to the container user to give ownership to the repository folder.
# See https://github.com/actions/checkout/issues/766
RUN groupadd --gid 1001 flutter \
    && useradd --create-home \
    --shell /bin/bash \
    --uid 1001 \
    --gid flutter \
    flutter
USER flutter:flutter
WORKDIR "$HOME"

ENV SDK_ROOT="$HOME/sdks"
ENV FLUTTER_ROOT="$SDK_ROOT/flutter"
ENV PATH="$PATH:$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin"

ARG flutter_version

RUN git clone \
    --depth 1 \
    --branch "$flutter_version" \
    https://github.com/flutter/flutter.git \
    "$FLUTTER_ROOT" \
    && chown -R flutter:flutter "$FLUTTER_ROOT" \
    && flutter --version \
    && flutter config --no-cli-animations \
    && dart --disable-analytics \
    && flutter config \
    --no-cli-animations \
    --no-analytics \
    --no-enable-android \
    --no-enable-web \
    --no-enable-linux-desktop \
    --no-enable-windows-desktop \
    --no-enable-fuchsia \
    --no-enable-custom-devices \
    --no-enable-ios \
    --no-enable-macos-desktop \
    && flutter doctor

COPY --chown=flutter:flutter ./script/docker_linux_entrypoint.sh "$HOME/docker_entrypoint.sh"
RUN chmod +x "$HOME/docker_entrypoint.sh"

ENTRYPOINT [ "/home/flutter/docker_entrypoint.sh" ]

FROM flutter AS android

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Get JAVA_HOME dinamically from a JDK binary 
# TODO: Use `dirname $(dirname $(readlink -f $(which javac)))` after the following issue is fixed
# TODO: https://github.com/moby/moby/issues/29110
ENV ANDROID_HOME="$SDK_ROOT/android-sdk" \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/.local/bin"

# renovate: release=bullseye depName=openjdk-17-jdk-headless
ARG OPENJDK_17_JDK_HEADLESS_VERSION="17.0.14+7-1~deb12u1"
# renovate: release=bullseye depName=sudo
ARG SUDO_VERSION="1.9.13p3-1+deb12u1"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # Android SDK dependencies
    ## JDK needs to be used instead of JRE because it provides the jlink tool used by the Android build
    openjdk-17-jdk-headless="$OPENJDK_17_JDK_HEADLESS_VERSION" \
    # To allow changing ownership in GitLab CI /builds
    sudo="$SUDO_VERSION" \
    && rm -rf /var/lib/apt/lists/* \
    # To allow changing ownership in GitLab CI /builds
    && echo "flutter ALL= NOPASSWD:/bin/chown -R flutter /builds, /bin/chown -R flutter /builds/*" >> /etc/sudoers.d/flutter

USER flutter:flutter
WORKDIR "$HOME"

ARG android_build_tools_version
ARG android_platform_versions
ARG android_ndk_version
ARG cmake_version

RUN mkdir -p "$ANDROID_HOME" \
    && chown -R flutter:flutter "$ANDROID_HOME" \
    && command_line_tools_url="$(curl -s https://developer.android.com/studio/ | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]\+_latest.zip')" \
    && curl -o android-cmdline-tools.zip "$command_line_tools_url" \
    && mkdir -p "$ANDROID_HOME/cmdline-tools/" \
    && unzip -q android-cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools/" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm android-cmdline-tools.zip \
    && (yes || true) | sdkmanager --licenses \
    && touch "$HOME/.android/repositories.cfg" \
    && mkdir -p "$HOME/.android" \
    && sdkmanager --update \
    && (yes || true) | sdkmanager \
    "platform-tools" \
    "build-tools;$android_build_tools_version" \
    "ndk;$android_ndk_version" \
    "cmake;$cmake_version" \
    && for version in $android_platform_versions; do (yes || true) | sdkmanager "platforms;android-$version"; done \
    && flutter config --enable-android \
    && (yes || true) | flutter doctor --android-licenses \
    && flutter precache --android \
    && flutter create build_app

WORKDIR "$HOME/build_app/android"
RUN ./gradlew --version

WORKDIR "$HOME"
RUN rm -r build_app
