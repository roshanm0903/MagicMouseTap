#!/bin/bash

# Build script for Roshan's personal Magic Mouse Tap app

APP_NAME="MagicMouseTap"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/Magic Mouse Tap.app"
MODULE_CACHE="$BUILD_DIR/ModuleCache"

# The macOS 26.7.1 update left the default MacOSX27 SDK one Swift patch behind
# the installed compiler. The bundled 26.5 SDK matches and is sufficient for
# this macOS 11+ app. MAGIC_MOUSE_TAP_SDK can override this later if needed.
SDK_PATH="${MAGIC_MOUSE_TAP_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

echo "=========================================="
echo "Building Magic Mouse Tap (Apple Silicon)"
echo "=========================================="

# Clean previous build
rm -rf "$APP_PATH"
rm -rf "$MODULE_CACHE"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$MODULE_CACHE"

# Compile for Apple Silicon (arm64)
echo "📦 Compiling for Apple Silicon (arm64)..."
swiftc -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macos11.0 \
    -import-objc-header MultitouchBridge.h \
    -framework Cocoa \
    -framework ApplicationServices \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Preferences.swift \
    DiagnosticLog.swift \
    SensitivityWindowController.swift \
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
