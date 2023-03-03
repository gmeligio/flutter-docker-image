docker build --target android --build-arg flutter_version=3.7.4 android_build_tools_version=30.0.3 --build-arg platforms_versions="28 31 33" -t android-test .
