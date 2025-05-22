FROM debian:12.11-slim@sha256:90522eeb7e5923ee2b871c639059537b30521272f10ca86fdbbbb2b75a8c40cd AS flutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV LANG=C.UTF-8

# renovate: release=bullseye depName=curl
ARG CURL_VERSION="7.88.1-10+deb12u12"
# renovate: release=bullseye depName=git
ARG GIT_VERSION="1:2.39.5-0+deb12u2"
# renovate: release=bullseye depName=lcov
ARG LCOV_VERSION="1.16-1"
# renovate: release=bullseye depName=ca-certificates
ARG CA_CERTIFICATES_VERSION="20230311"
# renovate: release=bullseye depName=unzip
ARG UNZIP_VERSION="6.0-28"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    # Flutter dependencies
    # bc=1.07.1-3build1 \
    # build-essential=12.9ubuntu3 \
    # For downloading Dart SDK
    curl="$CURL_VERSION" \
    git="$GIT_VERSION" \
    # For generating coverage reports
    lcov="$LCOV_VERSION" \
    # libglu1-mesa=9.0.2-1 \
    # libsqlite3-0=3.37.2-2ubuntu0.1 \
    # libstdc++6=12.1.0-2ubuntu1~22.04 \
    # libpulse0=1:15.99.1+dfsg1-1ubuntu2 \
    # locales=2.35-0ubuntu3.1 \
    # openssh-client=1:8.9p1-3ubuntu0.1 \
    # software-properties-common=0.99.22.5 \
    # zip=3.0-12build2 \
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

#-----------------------------------------------
#-----------------------------------------------
#-----------------------------------------------

FROM flutter AS fastlane

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# renovate: release=bullseye depName=ruby-dev
ARG RUBY_VERSION="1:3.1"
# renovate: release=bullseye depName=build-essential
ENV BUILD_ESSENTIAL_VERSION="12.9"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \ 
    # Fastlane dependencies
    ruby-full="$RUBY_VERSION" \
    build-essential="$BUILD_ESSENTIAL_VERSION" \
    && rm -rf /var/lib/apt/lists/*

USER flutter:flutter

ENV RUBY_ROOT="$SDK_ROOT/ruby"
ENV GEM_HOME="$RUBY_ROOT"
ENV GEM_PATH="$GEM_HOME"
ENV PATH="$PATH:$GEM_HOME/bin"

# Fastlane configuration
ENV FASTLANE_OPT_OUT_USAGE="YES"
ENV FASTLANE_SKIP_UPDATE_CHECK="YES"
ENV FASTLANE_HIDE_CHANGELOG="YES"

# renovate: datasource=rubygems depName=fastlane versioning=ruby
ENV BUNDLER_VERSION="2.4.14"

RUN gem install --no-document --version "$BUNDLER_VERSION" bundler

ENV FASTLANE_ROOT="$SDK_ROOT/fastlane"

RUN mkdir -p "$FASTLANE_ROOT"

WORKDIR "$FASTLANE_ROOT"

ARG fastlane_version

RUN bundle init \
    && bundle add --version "$fastlane_version" fastlane

#-----------------------------------------------
#-----------------------------------------------
#-----------------------------------------------

FROM fastlane AS android

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# TODO: Get JAVA_HOME dinamically from a JDK binary 
# TODO: Use `dirname $(dirname $(readlink -f $(which javac)))` after the following issue is fixed
# TODO: https://github.com/moby/moby/issues/29110
ENV ANDROID_HOME="$SDK_ROOT/android-sdk" \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/.local/bin"

# renovate: release=bullseye depName=openjdk-17-jdk-headless
ARG OPENJDK_17_JDK_HEADLESS_VERSION="17.0.15+6-1~deb12u1"
# renovate: release=bullseye depName=sudo
ARG SUDO_VERSION="1.9.13p3-1+deb12u1"

USER root
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
    # Installing deprecated Android SDK Tools (revision: 26.1.1)
    # Because Flutter always downloads it, even when it's not necessary, with log: "Install Android SDK Tools (revision: 26.1.1)"
    # && curl -o android-sdk-tools.zip https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip \
    # && mkdir -p "$ANDROID_HOME/" \
    # && unzip -q android-sdk-tools.zip -d "$ANDROID_HOME/" \
    # && rm android-sdk-tools.zip \
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
