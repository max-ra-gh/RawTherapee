#!/usr/bin/env bash
# Configure and build RawTherapee on macOS Apple Silicon with X3F support.
#
# Mirrors the upstream `armbuild` CI job in .github/workflows/macos.yml, with
# two changes for fast local testing:
#   - WITH_LTO=OFF       (LTO can triple link time for a test build)
#   - BUILD_BUNDLE=ON    (drops a self-contained, runnable install dir)
#
# Outputs:
#   build/   — CMake build dir
#   install/ — Self-contained RT bundle (run install/RawTherapee.app or
#              install/rawtherapee)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
INSTALL_DIR="$REPO_DIR/install"

BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"

CPU_COUNT="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

OMP_FLAGS="-arch arm64 -Xpreprocessor -fopenmp ${BREW_PREFIX}/opt/libomp/lib/libomp.dylib -I${BREW_PREFIX}/opt/libomp/include -I${BREW_PREFIX}/include -I${BREW_PREFIX}/opt/gdk-pixbuf/include -I${BREW_PREFIX}/opt/libiconv/include -I${BREW_PREFIX}/opt/libxml2/include -I${BREW_PREFIX}/opt/expat/include -I${BREW_PREFIX}/opt/libtiff/include"

export PKG_CONFIG_PATH="${BREW_PREFIX}/opt/libtiff/lib/pkgconfig:${BREW_PREFIX}/opt/libffi/lib/pkgconfig:${BREW_PREFIX}/opt/expat/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR"
cd "$BUILD_DIR"

echo "==> CMake configure"
cmake \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="Release" \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=OFF \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_EXE_LINKER_FLAGS="-L. -L${BREW_PREFIX}/lib -Wl,-rpath -Wl,${BREW_PREFIX}/lib -L${BREW_PREFIX}/opt/gdk-pixbuf/lib -L${BREW_PREFIX}/opt/libomp/lib -L${BREW_PREFIX}/opt/expat/lib" \
    -DCACHE_NAME_SUFFIX="x3f-test" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DWITH_LTO="OFF" \
    -DWITH_LIBRAW_X3F="ON" \
    -DOSX_DEV_BUILD="ON" \
    -DWITH_SIMDE="ON" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="-arch arm64 -Wno-pass-failed -Wno-deprecated-register -Wno-unused-command-line-argument" \
    -DCMAKE_CXX_FLAGS="-arch arm64 -Wno-pass-failed -Wno-deprecated-register -Wno-unused-command-line-argument" \
    -DOpenMP_C_FLAGS="${OMP_FLAGS}" \
    -DOpenMP_CXX_FLAGS="${OMP_FLAGS}" \
    -DOpenMP_C_LIB_NAMES=libomp \
    -DOpenMP_CXX_LIB_NAMES=libomp \
    -DOpenMP_libomp_LIBRARY="${BREW_PREFIX}/opt/libomp/lib/libomp.dylib" \
    -DCMAKE_AR=/usr/bin/ar \
    -DCMAKE_RANLIB=/usr/bin/ranlib \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DLOCAL_PREFIX="${BREW_PREFIX}" \
    -DBUILD_BUNDLE="ON" \
    -DBUNDLE_BASE_INSTALL_DIR="$INSTALL_DIR" \
    -DLENSFUNDBDIR="${BREW_PREFIX}/share/lensfun" \
    "$REPO_DIR"

echo
echo "==> Verifying USE_X3FTOOLS is in the LibRaw build"
if grep -R "USE_X3FTOOLS" rtengine/libraw-prefix/ rtengine/CMakeCache.txt 2>/dev/null | head -3; then
    echo "  (found above)"
else
    echo "  WARN: USE_X3FTOOLS not visible yet — LibRaw external project may not have been generated yet."
fi

echo
echo "==> Building with $CPU_COUNT jobs"
cmake --build . -j "$CPU_COUNT"

echo
echo "==> Installing to $INSTALL_DIR"
cmake --install .

echo
echo "==> Done."
ls -la "$INSTALL_DIR" 2>/dev/null | head -20
echo
echo "Launch GUI:    open '$INSTALL_DIR/RawTherapee.app' || '$INSTALL_DIR/rawtherapee'"
echo "Launch CLI:    '$INSTALL_DIR/rawtherapee-cli' --help"
