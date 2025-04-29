#!/usr/bin/env bash

docker build --target android --build-arg flutter_version=3.19.0 --build-arg android_build_tools_version=30.0.3 --build-arg android_platform_versions="28 31 33 34 35" -t android-test .
