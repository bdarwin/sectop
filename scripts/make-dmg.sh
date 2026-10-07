#!/usr/bin/env bash
# Packages dist/Sectop.app into dist/Sectop-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Sectop.app/Contents/Info.plist)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R dist/Sectop.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "dist/Sectop-$VERSION.dmg"
hdiutil create -volname "Sectop $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "dist/Sectop-$VERSION.dmg"
echo "Created dist/Sectop-$VERSION.dmg"
