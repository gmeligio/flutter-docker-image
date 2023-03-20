# TODO: Use debian-slim as base image
FROM public.ecr.aws/ubuntu/ubuntu:22.04@sha256:234afeb5d15478d2f8066f3610211fa641c0cd9b551e4ecc64ca93a05c1df5cf as flutter

# TODO: https://github.dev/circleci/circleci-images
# TODO: https://github.dev/cirruslabs/docker-images-android
# TODO: https://github.dev/mingchen/docker-android-build-box/tree/master

# TODO: Get latest version of flutter from GitHub GraphQL API https://docs.github.com/en/graphql/overview/explorer

# TODO: https://github.dev/cirruslabs/docker-images-flutter
# TODO: https://github.dev/instrumentisto/flutter-docker-image
# TODO: https://github.dev/gmemstr/flutter-fastlane-android
# TODO: https://github.dev/fischerscode/DockerFlutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV LANG=C.UTF-8

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # Flutter dependencies
    # bc=1.07.1-3build1 \
    # build-essential=12.9ubuntu3 \
    curl=7.81.0-1ubuntu1.8 \
    git=1:2.34.1-1ubuntu1.8 \
    lcov=1.15-1 \
    # libglu1-mesa=9.0.2-1 \
    # libsqlite3-0=3.37.2-2ubuntu0.1 \
    # libstdc++6=12.1.0-2ubuntu1~22.04 \
    # libpulse0=1:15.99.1+dfsg1-1ubuntu2 \
    # locales=2.35-0ubuntu3.1 \
    # openssh-client=1:8.9p1-3ubuntu0.1 \
    # ruby-bundler=2.3.5-2 \
    # ruby-full=1:3.0~exp1 \
    # software-properties-common=0.99.22.5 \
    ca-certificates=20211016ubuntu0.22.04.1 \
    # sudo=1.9.9-1ubuntu2.2 \
    unzip=6.0-26ubuntu3.1 \
    # zip=3.0-12build2 \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/home/flutter

RUN useradd -Ums /bin/bash flutter
USER flutter:flutter
WORKDIR "$HOME"

ENV FLUTTER_ROOT="$HOME/sdks/flutter"
ENV PATH="$PATH:$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin"

ARG flutter_version

RUN git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
    && chown -R flutter:flutter "$FLUTTER_ROOT" \
    && flutter --version \
    && dart --disable-analytics \
    && flutter config --no-analytics \
    && flutter config --no-enable-android \
    && flutter config --no-enable-web \
    && flutter config --no-enable-linux-desktop \
    && flutter config --no-enable-windows-desktop \
    && flutter config --no-enable-fuchsia \
    && flutter config --no-enable-custom-devices \
    && flutter config --no-enable-ios \
    && flutter config --no-enable-macos-desktop \
    && flutter doctor

COPY ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]

FROM flutter as android

LABEL org.opencontainers.image.source="https://github.com/gmeligio/flutter-docker-image" \
    org.opencontainers.image.url="https://github.com/gmeligio/flutter-docker-image" \
    org.opencontainers.image.documentation="https://github.com/gmeligio/flutter-docker-image" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.authors="Eligio Mariño" \
    org.opencontainers.image.vendor="Eligio Mariño" \
    org.opencontainers.image.title="Flutter Docker Image"

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Get JAVA_HOME dinamically from a JDK binary 
ENV ANDROID_HOME="$HOME/sdks/android-sdk" \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/.local/bin"

USER root
# hadolint ignore=DL3003
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # For Android x86 emulators
    # libxtst6=2:1.2.3-1build4 \
    # libnss3-dev=2:3.68.2-0ubuntu1.1 \
    # libnspr4=2:4.32-3build1 \
    # libxss1=1:1.2.3-1build2 \
    # libasound2=1.2.6.1-1ubuntu1 \
    # libatk-bridge2.0-0=2.38.0-3 \
    # libgtk-3-0=3.24.33-1ubuntu2 \
    # libgdk-pixbuf2.0-0=2.40.2-2build4 \
    # Android SDK dependencies
    openjdk-11-jdk=11.0.18+10-0ubuntu1~22.04 \
    # To allow changing ownership in GitLab CI /builds
    sudo=1.9.9-1ubuntu2.3 \
    && rm -rf /var/lib/apt/lists/* \
    # To allow changing ownership in GitLab CI /builds
    && echo "flutter ALL= NOPASSWD:/bin/chown -R flutter /builds, /bin/chown -R flutter /builds/*" >> /etc/sudoers.d/flutter

USER flutter:flutter
WORKDIR "$HOME"

ARG android_build_tools_version
ARG platforms_versions

# hadolint ignore=DL3003
RUN mkdir -p "$ANDROID_HOME" \
    && chown -R flutter:flutter "$ANDROID_HOME" \
    && command_line_tools_url="$(curl -s https://developer.android.com/studio/ | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]\{7\}_latest.zip')" \
    && curl -o android-cmdline-tools.zip "$command_line_tools_url" \
    && mkdir -p "$ANDROID_HOME/cmdline-tools/" \
    && unzip -q android-cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools/" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm android-cmdline-tools.zip \
    # Installing deprecated Android SDK Tools (revision: 26.1.1)
    # Because Flutter always downloads it, even when it's not necessary, with log: "Install Android SDK Tools (revision: 26.1.1)"
    && curl -o android-sdk-tools.zip https://dl.google.com/android/repository/sdk-tools-windows-4333796.zip \
    && mkdir -p "$ANDROID_HOME/" \
    && unzip -q android-sdk-tools.zip -d "$ANDROID_HOME/" \
    && rm android-sdk-tools.zip \
    && (yes || true) | sdkmanager --licenses \
    # && mkdir -p "$HOME/.local/bin" \
    # && curl -o "$HOME/.local/bin/android-wait-for-emulator" https://raw.githubusercontent.com/travis-ci/travis-cookbooks/master/community-cookbooks/android-sdk/files/default/android-wait-for-emulator \
    # && chmod +x "$HOME/.local/bin/android-wait-for-emulator" \
    && touch "$HOME/.android/repositories.cfg" \
    # && sdkmanager platform-tools \
    && mkdir -p "$HOME/.android" \
    # && touch "$HOME/.android/repositories.cfg" \
    # && if [ "$(uname -m)" = "x86_64" ] ; then sdkmanager emulator ; fi \
    && sdkmanager --update \
    && (yes || true) | sdkmanager \
    "platform-tools" \
    "build-tools;$android_build_tools_version" \
    && for version in $platforms_versions; do (yes || true) | sdkmanager "platforms;android-$version"; done \
    && flutter config --enable-android \
    && (yes || true) | flutter doctor --android-licenses \
    && flutter precache --android \
    && flutter create build_app \
    && cd build_app/android \
    && ./gradlew --version \
    && cd ../.. \
    && rm -r build_app

FROM android as android-test

USER flutter:flutter
WORKDIR "$HOME"

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN flutter create test_app

WORKDIR "$HOME/test_app/android"
RUN ./gradlew assembleRelease \
    && ./gradlew bundleRelease

WORKDIR "$HOME/test_app"
RUN flutter build appbundle
