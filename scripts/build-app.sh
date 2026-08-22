#!/bin/bash
# Assemble BongoTokenCat.app from the SwiftPM build product.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="BongoTokenCat"
VERSION="0.1.0"
# Conductor workspaces live on a filesystem where SwiftPM's SQLite build database
# fails with a disk I/O error, so the scratch directory is kept outside the repo.
SCRATCH="${SCRATCH_PATH:-/tmp/bongo-build}"
OUT="build"
APP="$OUT/$APP_NAME.app"

echo "==> swift build -c release"
# Only the app product: BongoTests uses `@testable import`, which release builds
# reject because they are not compiled for testing.
swift build -c release --scratch-path "$SCRATCH" --product "$APP_NAME"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SCRATCH/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM emits resources as a sibling bundle next to the binary. Without it the
# app launches and draws nothing, so a missing bundle is a hard failure.
# -L because SwiftPM's "release" is a symlink to the arch-specific directory.
BUNDLE=$(find -L "$SCRATCH/release" -maxdepth 1 -name '*BongoKit.bundle' -print -quit)
[ -n "$BUNDLE" ] || { echo "no resource bundle found in $SCRATCH/release" >&2; exit 1; }
cp -R "$BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.lucasoyarzun.bongotokencat</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (unsigned — fine for local use)"
echo "==> built $APP"
