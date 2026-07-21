#!/bin/bash
#
# Build the FreenectTOP TouchDesigner plugin for Intel (x86_64) macs using only
# the Command Line Tools (clang) — no full Xcode required.
#
# Output: build/FreenectTOP.plugin
# Pass --install to also copy it into TouchDesigner's global Plugins folder.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="x86_64"
MIN_OS="12.4"
PLUGIN_NAME="FreenectTOP"
TD_VERSION="2025"
VERSION="1.1.0"

BUILD_DIR="$REPO_ROOT/build"
OBJ_DIR="$BUILD_DIR/obj"
BUNDLE="$BUILD_DIR/${PLUGIN_NAME}.plugin"
MACOS_DIR="$BUNDLE/Contents/MacOS"

rm -rf "$BUILD_DIR"
mkdir -p "$OBJ_DIR" "$MACOS_DIR"

SOURCES=(
    "FreenectTOP.cpp"
    "FreenectV1.cpp"
    "FreenectV2.cpp"
    "ofxKinectExtras/ofxKinectExtras.cpp"
)

CXXFLAGS=(
    -arch "$ARCH"
    -mmacosx-version-min="$MIN_OS"
    -std=gnu++17
    -O2
    -Wno-invalid-offsetof
    -I"$REPO_ROOT"
    -I"$REPO_ROOT/include/headers"
    -I"$REPO_ROOT/ofxKinectExtras"
    -DTD_VERSION="$TD_VERSION"
    -DFNTD_DEBUG=0
    -DFNTD_PROFILE=0
    "-DFREENECTTOP_VERSION=\"$VERSION\""
)

echo "==> Compiling sources ($ARCH)"
OBJECTS=()
for src in "${SOURCES[@]}"; do
    obj="$OBJ_DIR/$(basename "${src%.cpp}").o"
    echo "    $src"
    clang++ "${CXXFLAGS[@]}" -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

echo "==> Linking bundle"
clang++ \
    -bundle \
    -arch "$ARCH" \
    -mmacosx-version-min="$MIN_OS" \
    "${OBJECTS[@]}" \
    "$REPO_ROOT/include/libs/libfreenect2_0.2.0.a" \
    "$REPO_ROOT/include/libs/libfreenect_0.7.5.a" \
    "$REPO_ROOT/include/libs/libusb_1.0.29.a" \
    -framework Accelerate \
    -framework CoreFoundation \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework VideoToolbox \
    -framework IOKit \
    -framework Security \
    -lobjc \
    -o "$MACOS_DIR/$PLUGIN_NAME"

echo "==> Writing Info.plist"
cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${PLUGIN_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>ee.marte.FreenectTD.TOP</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${PLUGIN_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS}</string>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Built: $BUNDLE"
lipo -archs "$MACOS_DIR/$PLUGIN_NAME"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Library/Application Support/Derivative/TouchDesigner099/Plugins"
    mkdir -p "$DEST"
    rm -rf "$DEST/${PLUGIN_NAME}.plugin"
    ditto "$BUNDLE" "$DEST/${PLUGIN_NAME}.plugin"
    echo "==> Installed to: $DEST/${PLUGIN_NAME}.plugin"
fi
