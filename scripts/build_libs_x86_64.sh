#!/bin/bash
#
# Rebuild the bundled static libraries (libusb, libfreenect, libfreenect2) for
# Intel (x86_64) macs and drop them into include/libs/ with the filenames the
# Xcode project / plugin build expect.
#
# Requires: git, cmake, autoconf, automake, libtool, pkg-config
#   brew install cmake autoconf automake libtool pkg-config
#
# libfreenect2 is built VideoToolbox-only (OpenGL/OpenCL/TurboJPEG disabled) so
# the resulting archive has no external dynamic dependencies beyond system
# frameworks. The plugin only uses libfreenect2::CpuPacketPipeline, whose RGB
# (JPEG) decode is handled by VideoToolbox on macOS.
#
set -euo pipefail

ARCH="x86_64"
MIN_OS="12.4"
LIBUSB_TAG="v1.0.29"
FREENECT_TAG="v0.7.5"
# NOTE: libfreenect2 is pinned to a master commit, NOT the v0.2.0 release tag.
# The bundled public headers in include/headers/libfreenect2/ are from master
# (they declare post-0.2.0 API such as setColorAutoExposure/ColorSettingCommandType/
# Freenect2Replay). Building from the v0.2.0 tag produces a different
# Freenect2Device vtable layout, so virtual calls (e.g. startStreams) dispatch
# to the wrong slot and crash (SIGBUS). This commit matches the bundled headers.
FREENECT2_REF="fd64c5d"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_LIBS="$REPO_ROOT/include/libs"
WORK="${TMPDIR:-/tmp}/fnbuild"
PREFIX="$WORK/prefix"

mkdir -p "$WORK" "$PREFIX"

# ---------------------------------------------------------------- libusb
cd "$WORK"
rm -rf libusb
git clone --depth 1 --branch "$LIBUSB_TAG" https://github.com/libusb/libusb.git
cd libusb
./bootstrap.sh
./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-udev \
    CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS"
make -j"$(sysctl -n hw.ncpu)"
make install

# ---------------------------------------------------------------- libfreenect
cd "$WORK"
rm -rf libfreenect
git clone --depth 1 --branch "$FREENECT_TAG" https://github.com/OpenKinect/libfreenect.git
cd libfreenect
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" cmake -S . -B build \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_OS" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_FAKENECT=OFF \
    -DBUILD_CPACK_DEB=OFF -DBUILD_CV=OFF -DBUILD_AS3_SERVER=OFF \
    -DBUILD_PYTHON=OFF -DBUILD_AUDIO=ON
# The static target ('freenectstatic') is all we need; the shared target may
# fail to link (it lacks the CoreFoundation/IOKit frameworks), so ignore that.
cmake --build build --target freenectstatic -j"$(sysctl -n hw.ncpu)"

# ---------------------------------------------------------------- libfreenect2
cd "$WORK"
rm -rf libfreenect2
git clone https://github.com/OpenKinect/libfreenect2.git
cd libfreenect2
git checkout "$FREENECT2_REF"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" cmake -S . -B build \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_OS" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_OPENNI2_DRIVER=OFF \
    -DENABLE_OPENGL=OFF -DENABLE_OPENCL=OFF -DENABLE_CUDA=OFF \
    -DENABLE_TEGRAJPEG=OFF -DENABLE_VAAPI=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_TurboJPEG=TRUE
cmake --build build -j"$(sysctl -n hw.ncpu)"

# ---------------------------------------------------------------- install
cp "$PREFIX/lib/libusb-1.0.a"          "$REPO_LIBS/libusb_1.0.29.a"
cp "$WORK/libfreenect/build/lib/libfreenect.a"   "$REPO_LIBS/libfreenect_0.7.5.a"
cp "$WORK/libfreenect2/build/lib/libfreenect2.a" "$REPO_LIBS/libfreenect2_0.2.0.a"

# Keep the bundled config.h in sync with the way libfreenect2 was built.
cp "$WORK/libfreenect2/build/libfreenect2/config.h" \
   "$REPO_ROOT/include/headers/libfreenect2/config.h"

# Keep the bundled public headers in sync with the exact source the library was
# built from. The Freenect2Device vtable layout is defined by these headers, so
# they MUST match the compiled archive or virtual dispatch will crash.
for h in libfreenect2.hpp frame_listener.hpp frame_listener_impl.h registration.h \
         packet_pipeline.h logger.h color_settings.h led_settings.h export.h; do
    cp "$WORK/libfreenect2/include/libfreenect2/$h" \
       "$REPO_ROOT/include/headers/libfreenect2/$h" 2>/dev/null || true
done

echo "==> Installed x86_64 static libraries:"
for f in "$REPO_LIBS"/*.a; do printf "    %s: " "$f"; lipo -archs "$f"; done
