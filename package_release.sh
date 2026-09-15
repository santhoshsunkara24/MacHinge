#!/bin/bash
set -euo pipefail

echo "============================================================"
echo "          Building MacHinge 0.1.0 Release Distribution"
echo "============================================================"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# 1. Clean & Build Release via SwiftPM
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
swift build -c release

BIN_PATH="$PROJECT_DIR/.build/release/MacHinge"
if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: Release binary not found at $BIN_PATH"
    exit 1
fi

# 2. Prepare Release App Bundle Structure
echo "==> Constructing MacHinge.app bundle..."
RELEASE_DIR="$PROJECT_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/MacHinge.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BIN_PATH" "$MACOS_DIR/MacHinge"
chmod +x "$MACOS_DIR/MacHinge"

# Copy Icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$PROJECT_DIR/AppIcon.png" ]; then
    cp "$PROJECT_DIR/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
fi

# Copy Shader source
cp "$PROJECT_DIR/Sources/MacHinge/Metal/Shaders.metal" "$RESOURCES_DIR/Shaders.metal"

# Copy bundle resources if SwiftPM generated a bundle
if [ -d "$PROJECT_DIR/.build/release/MacHinge_MacHinge.bundle" ]; then
    cp -R "$PROJECT_DIR/.build/release/MacHinge_MacHinge.bundle" "$RESOURCES_DIR/"
fi

# Write Info.plist
cat << 'PLIST_EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacHinge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.machinge.MacHinge</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacHinge</string>
    <key>CFBundleDisplayName</key>
    <string>MacHinge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableDescription</key>
    <string>MacBook lid-driven display folding transition.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST_EOF

# Write PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Ad-hoc sign bundle for local arm64 execution with permanent designated requirement
echo "==> Ad-hoc signing bundle with stable designated requirement..."
codesign --force --deep --sign - --identifier "com.machinge.MacHinge" -r="designated => identifier \"com.machinge.MacHinge\"" "$APP_BUNDLE"

# 3. Create Distribution ZIP
echo "==> Creating ZIP archive..."
ZIP_PATH="$RELEASE_DIR/MacHinge-0.1.0.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# 4. Create Distribution DMG
echo "==> Creating DMG image..."
DMG_PATH="$RELEASE_DIR/MacHinge-0.1.0.dmg"
rm -f "$DMG_PATH"

TMP_DMG_DIR="$PROJECT_DIR/.build/dmg_tmp"
rm -rf "$TMP_DMG_DIR"
mkdir -p "$TMP_DMG_DIR"
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"
cp "$RELEASE_DIR/README.txt" "$TMP_DMG_DIR/"
cp "$RELEASE_DIR/INSTALL.txt" "$TMP_DMG_DIR/"
cp "$RELEASE_DIR/CHANGELOG.txt" "$TMP_DMG_DIR/"

hdiutil create -volname "MacHinge" -srcfolder "$TMP_DMG_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DMG_DIR"

# Also copy to Installer filename for URL compatibility
cp "$DMG_PATH" "$RELEASE_DIR/MacHinge-0.1.0-Installer.dmg"

echo "============================================================"
echo "          Release Package Build Completed Successfully"
echo "============================================================"
