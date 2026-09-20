#!/bin/bash

# Build script for Roshan's personal Magic Mouse Tap app

APP_NAME="MagicMouseTap"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/Magic Mouse Tap.app"

echo "=========================================="
echo "Building Magic Mouse Tap (Apple Silicon)"
echo "=========================================="

# Clean previous build
rm -rf "$APP_PATH"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Compile for Apple Silicon (arm64)
echo "📦 Compiling for Apple Silicon (arm64)..."
swiftc -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macos11.0 \
    -import-objc-header MultitouchBridge.h \
    -framework Cocoa \
    -framework ApplicationServices \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Preferences.swift \
    DiagnosticLog.swift \
    TapDetector.swift \
    TwoFingerTapDetector.swift \
    MultitouchManager.swift \
    AppDelegate.swift \
    main.swift

if [ $? -ne 0 ]; then
    echo "❌ arm64 compilation failed!"
    exit 1
fi

# Copy Info.plist
cp Info.plist "$APP_PATH/Contents/"
cp LICENSE "$APP_PATH/Contents/Resources/MouseToucher-MIT-LICENSE.txt"

# Sign with Roshan's stable local code-signing identity so Accessibility permission
# remains attached across local rebuilds.
echo "[34m[1m[0m"
echo "[34m[1m[0m"
echo "[34m[1mCodesigning app bundle...[0m"
codesign --force --deep --sign "Magic Mouse Tap Local" "$APP_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Codesigning failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ BUILD COMPLETE!"
echo "=========================================="
echo ""
echo "App location: $APP_PATH"
echo "Architecture: arm64 (Apple Silicon)"
echo ""
echo "To run the app:"
echo "  open $APP_PATH"
echo ""
echo "To install the app (copy to Applications):"
echo "  cp -r $APP_PATH /Applications/"
echo ""
