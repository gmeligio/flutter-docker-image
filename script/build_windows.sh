# cmake generate
cmake -S . -B ../build/windows/x64 -G "Visual Studio 16 2019" -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64

# cmake build
cmake --build ../build/windows/x64 --config Release --target INSTALL --verbose
