#!/bin/sh
# Builds a universal Switchboard.app and packs it for download: dist/Switchboard-<version>.zip and .dmg.
# VERSION=0.2.0 sh scripts/release.sh   (default: the version in bundle.sh)
set -eu
cd "$(dirname "$0")/.."

UNIVERSAL=1 sh scripts/bundle.sh
V="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Switchboard.app/Contents/Info.plist)"

rm -f "dist/Switchboard-$V.zip" "dist/Switchboard-$V.dmg"
# ditto keeps the bundle's signature and attributes, unlike zip
ditto -c -k --keepParent dist/Switchboard.app "dist/Switchboard-$V.zip"

# disk image with the app and a shortcut to Applications, to drag it across
STAGE="$(mktemp -d)"
cp -R dist/Switchboard.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Switchboard -srcfolder "$STAGE" -ov -format UDZO "dist/Switchboard-$V.dmg"
rm -rf "$STAGE"

echo "dist/Switchboard-$V.zip"
echo "dist/Switchboard-$V.dmg"
