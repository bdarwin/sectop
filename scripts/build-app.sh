#!/usr/bin/env bash
# Builds a universal dist/Sectop.app.
#   VERSION=1.2.3       version string (default: latest git tag, else 0.0.0)
#   SIGN_IDENTITY=...   codesign identity (default: "-" = ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)"
fi
VERSION="${VERSION#v}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="dist/Sectop.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Sectop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sectop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, signed with '$SIGN_IDENTITY')"
