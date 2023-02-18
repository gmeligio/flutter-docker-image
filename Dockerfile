FROM ubuntu:22.04 as base

# TODO: https://github.dev/circleci/circleci-images
# TODO: https://github.dev/cirruslabs/docker-images-android
# TODO: https://github.dev/mingchen/docker-android-build-box/tree/master

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Remove root user
# hadolint ignore=DL3002
USER root

ENV ANDROID_HOME=/opt/android-sdk-linux \
    LANG=C.UTF-8

ENV ANDROID_SDK_ROOT=$ANDROID_HOME \
    PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator

WORKDIR /opt

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    openjdk-11-jdk=11.0.17+8-1ubuntu2~22.04 \
    sudo=1.9.9-1ubuntu2.2 \
    zip=3.0-12build2 \
    unzip=6.0-26ubuntu3.1 \
    git=1:2.34.1-1ubuntu1.8 \
    openssh-client=1:8.9p1-3ubuntu0.1 \
    curl=7.81.0-1ubuntu1.7 \
    bc=1.07.1-3build1 \
    software-properties-common=0.99.22.5 \
    build-essential=12.9ubuntu3 \
    ruby-full=1:3.0~exp1 \
    ruby-bundler=2.3.5-2 \
    libstdc++6=12.1.0-2ubuntu1~22.04 \
    libpulse0=1:15.99.1+dfsg1-1ubuntu2 \
    libglu1-mesa=9.0.2-1 \
    locales=2.35-0ubuntu3.1 \
    lcov=1.15-1 \
    libsqlite3-0=3.37.2-2ubuntu0.1 \
    # for x86 emulators
    libxtst6=2:1.2.3-1build4 \
    libnss3-dev=2:3.68.2-0ubuntu1.1 \
    libnspr4=2:4.32-3build1 \
    libxss1=1:1.2.3-1build2 \
    libasound2=1.2.6.1-1ubuntu1 \
    libatk-bridge2.0-0=2.38.0-3 \
    libgtk-3-0=3.24.33-1ubuntu2 \
    libgdk-pixbuf2.0-0=2.40.2-2build4 \
    && rm -rf /var/lib/apt/lists/* \
    && command_line_tools_url="$(curl -s https://developer.android.com/studio/ | grep -o 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]\{7\}_latest.zip')" \
    && curl -o android-sdk-tools.zip "$command_line_tools_url" \
    && mkdir -p "${ANDROID_HOME}/cmdline-tools/" \
    && unzip -q android-sdk-tools.zip -d "${ANDROID_HOME}/cmdline-tools/" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
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
    && if [ "$(uname -m)" = "x86_64" ] ; then sdkmanager emulator ; fi

FROM base as sdk

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN sdkmanager --update \
    && build_tools_descriptor=$(sdkmanager --list | grep 'build-tools' | awk '{print $1}' | grep -oP 'build-tools;\d+\.\d+\.\d+$' | tail -1) \
    && platforms_version=$(sdkmanager --list | grep 'platforms;android' | awk '{print $1}' | grep -oP '\d+$' | sort -n | tail -1) \
    && (yes || true) | sdkmanager \
    "$build_tools_descriptor" \
    "platforms;android-$platforms_version"

FROM sdk as ndk

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN sdkmanager --update \
    && ndk_descriptor=$(sdkmanager --list | grep 'ndk' | awk '{print $1}' | grep -oP 'ndk;\d+\.\d+\.\d+$' | tail -1) \
    && (yes || true) | sdkmanager "$ndk_descriptor"

FROM ndk as flutter

# TODO: Get latest version of flutter from GitHub GraphQL API https://docs.github.com/en/graphql/overview/explorer

# TODO: https://github.dev/cirruslabs/docker-images-flutter
# TODO: https://github.dev/instrumentisto/flutter-docker-image
# TODO: https://github.dev/gmemstr/flutter-fastlane-android
# TODO: https://github.dev/fischerscode/DockerFlutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Remove root user
# hadolint ignore=DL3002
USER root

# ARG flutter_version

ENV FLUTTER_HOME=${HOME}/sdks/flutter \
    # FLUTTER_VERSION=$flutter_version
    FLUTTER_VERSION=3.7.1
ENV FLUTTER_ROOT=$FLUTTER_HOME

ENV PATH ${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN (yes || true) | flutter doctor --android-licenses \
    && flutter doctor \
    && chown -R root:root ${FLUTTER_HOME}
