#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AnyPiP"
BUILD_CONFIG="release"

cd "$ROOT_DIR"
echo "Compilation de $APP_NAME ($BUILD_CONFIG)…"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/AnyPiP"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/AnyPiP"
cp "$ROOT_DIR/config/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/Resources/en.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"

DEV_CERT_NAME="MacPiP Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_CERT_NAME"; then
    echo "Signature avec l'identité locale stable \"$DEV_CERT_NAME\"…"
    codesign --force --deep --sign "$DEV_CERT_NAME" "$APP_BUNDLE"
else
    echo "Pas d'identité stable trouvée — signature ad-hoc (voir scripts/create_dev_certificate.sh)."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "App générée : $APP_BUNDLE"
echo "Lancement…"
open "$APP_BUNDLE"
