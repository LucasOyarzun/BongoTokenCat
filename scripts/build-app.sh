#!/bin/bash
# Assemble BongoTokenCat.app from the SwiftPM build product.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="BongoTokenCat"
# Kept separate from APP_NAME even though they match today: one names the product,
# the other has to track Package.swift's `name:` for the resource bundle lookup.
PACKAGE_NAME="BongoTokenCat"
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
# SwiftPM emits resources as a sibling bundle next to the binary, named
# "<package>_<target>.bundle" — the exact name `Bundle.module` looks for at
# runtime. Match it exactly rather than globbing: a scratch directory that has
# survived a package rename holds bundles under both names, and copying the wrong
# one produces an app that builds cleanly and then traps on launch.
RESOURCE_BUNDLE="${PACKAGE_NAME}_BongoKit.bundle"
BUNDLE="$SCRATCH/release/$RESOURCE_BUNDLE"
[ -d "$BUNDLE" ] || { echo "no $RESOURCE_BUNDLE in $SCRATCH/release" >&2; exit 1; }
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
