# TODO: Use debian-slim as base image
FROM public.ecr.aws/ubuntu/ubuntu:22.04@sha256:234afeb5d15478d2f8066f3610211fa641c0cd9b551e4ecc64ca93a05c1df5cf as flutter

# TODO: Supress usage statistics from all tools, including Flutter
# TODO: Arguments to enable usage statistics from all tools, including Flutter

# TODO: https://github.dev/circleci/circleci-images
# TODO: https://github.dev/cirruslabs/docker-images-android
# TODO: https://github.dev/mingchen/docker-android-build-box/tree/master

# TODO: Get latest version of flutter from GitHub GraphQL API https://docs.github.com/en/graphql/overview/explorer

# TODO: https://github.dev/cirruslabs/docker-images-flutter
# TODO: https://github.dev/instrumentisto/flutter-docker-image
# TODO: https://github.dev/gmemstr/flutter-fastlane-android
# TODO: https://github.dev/fischerscode/DockerFlutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Remove root user
# hadolint ignore=DL3002
USER root

ARG flutter_version

ENV LANG=C.UTF-8 \
    FLUTTER_ROOT="$HOME/sdks/flutter"
ENV PATH="$PATH:$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin"

WORKDIR /opt

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # Flutter dependencies
    # bc=1.07.1-3build1 \
    # build-essential=12.9ubuntu3 \
    curl=7.81.0-1ubuntu1.7 \
    git=1:2.34.1-1ubuntu1.8 \
    # lcov=1.15-1 \
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
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
    && chown -R root:root "$FLUTTER_ROOT" \
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

FROM flutter as android

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ARG android_build_tools_version

ENV ANDROID_HOME=/opt/android-sdk-linux
ENV ANDROID_SDK_ROOT="$ANDROID_HOME" \
    PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

# hadolint ignore=DL3003
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # for x86 emulators
    # libxtst6=2:1.2.3-1build4 \
    # libnss3-dev=2:3.68.2-0ubuntu1.1 \
    # libnspr4=2:4.32-3build1 \
    # libxss1=1:1.2.3-1build2 \
    # libasound2=1.2.6.1-1ubuntu1 \
    # libatk-bridge2.0-0=2.38.0-3 \
    # libgtk-3-0=3.24.33-1ubuntu2 \
    # libgdk-pixbuf2.0-0=2.40.2-2build4 \
    # Android SDK dependencies
    openjdk-11-jdk=11.0.17+8-1ubuntu2~22.04 \
    && rm -rf /var/lib/apt/lists/* \
    && command_line_tools_url="$(curl -s https://developer.android.com/studio/ | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]\{7\}_latest.zip')" \
    && curl -o android-sdk-tools.zip "$command_line_tools_url" \
    && mkdir -p "$ANDROID_HOME/cmdline-tools/" \
    && unzip -q android-sdk-tools.zip -d "$ANDROID_HOME/cmdline-tools/" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && chown -R root:root "$ANDROID_HOME" \
    && rm android-sdk-tools.zip \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && (yes || true) | sdkmanager --licenses \
    && curl -o /usr/bin/android-wait-for-emulator https://raw.githubusercontent.com/travis-ci/travis-cookbooks/master/community-cookbooks/android-sdk/files/default/android-wait-for-emulator \
    && chmod +x /usr/bin/android-wait-for-emulator \
    && touch /root/.android/repositories.cfg \
    && sdkmanager platform-tools \
    && mkdir -p /root/.android \
    && touch /root/.android/repositories.cfg \
    && if [ "$(uname -m)" = "x86_64" ] ; then sdkmanager emulator ; fi \
    && sdkmanager --update \
    && platforms_version=$(sdkmanager --list | grep 'platforms;android' | awk '{print $1}' | grep -oP '\d+$' | sort -n | tail -1) \
    # && ndk_descriptor=$(sdkmanager --list | grep 'ndk' | awk '{print $1}' | grep -oP 'ndk;\d+\.\d+\.\d+$' | tail -1) \
    && (yes || true) | sdkmanager \
    "build-tools;$android_build_tools_version" \
    "platforms;android-$platforms_version" \
    # "$ndk_descriptor" \
    && flutter config --enable-android \
    && flutter config --android-sdk "$ANDROID_HOME" \
    && (yes || true) | flutter doctor --android-licenses \
    && flutter precache --android \
    && flutter create build_app \
    && cd build_app/android \
    && ./gradlew --version \
    && cd ../.. \
    && rm -r build_app

FROM android as android-test

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

WORKDIR /root

RUN flutter create test_app

WORKDIR /root/test_app/android
RUN ./gradlew assembleRelease
