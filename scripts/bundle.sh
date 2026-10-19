#!/bin/sh
# Builds a release and wraps it as Switchboard.app in dist/. With --install, copies it to ~/Applications
# (SWITCHBOARD_INSTALL=<folder> for another one) and opens it.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
# UNIVERSAL=1 adds Intel (for releases): one build per architecture, joined with lipo. (`--arch arm64
# --arch x86_64` goes through xcbuild, which can't resolve SwiftTerm's build plugin.)
if [ "${UNIVERSAL:-}" = "1" ]; then
    for arch in arm64 x86_64; do swift build -c release --triple "$arch-apple-macosx14.0"; done
    FAT="$(mktemp -d)"
    for exe in Switchboard switchboard-statusline switchboard-task; do
        lipo -create -output "$FAT/$exe" .build/arm64-apple-macosx/release/$exe .build/x86_64-apple-macosx/release/$exe
    done
fi
APP="dist/Switchboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "${FAT:-$BIN}/Switchboard" "$APP/Contents/MacOS/Switchboard"
# status line helper; the app copies it to ~/.switchboard/bin when you set up the live status line
cp "${FAT:-$BIN}/switchboard-statusline" "$APP/Contents/MacOS/switchboard-statusline"
# handover helper; the app copies it to ~/.switchboard/bin when you set up the handover
cp "${FAT:-$BIN}/switchboard-task" "$APP/Contents/MacOS/switchboard-task"
# SwiftPM resource bundles (SwiftTerm's shaders): SwiftTerm also looks in Contents/Resources, which keeps
# the app's root clean so the whole bundle can be signed
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# icon: the app draws its own mark (AppMark) into an iconset
ICONSET="$(mktemp -d)/AppIcon.iconset"
# ICON_STYLE=hub sh scripts/bundle.sh picks another design (see IconStyle)
"$BIN/Switchboard" ${ICON_STYLE:+-iconStyle "$ICON_STYLE"} --export-icon "$ICONSET" && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || echo "icon skipped"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Switchboard</string>
    <key>CFBundleDisplayName</key><string>Switchboard</string>
    <key>CFBundleIdentifier</key><string>dev.local.switchboard</string>
    <key>CFBundleExecutable</key><string>Switchboard</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
# ad-hoc signature over the whole bundle (no Apple Developer ID): a downloaded copy then opens after
# "Open Anyway" in System Settings → Privacy & Security instead of being reported as damaged
codesign --force --deep --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
    DEST="${SWITCHBOARD_INSTALL:-$HOME/Applications}"
    mkdir -p "$DEST"
    rm -rf "$DEST/Switchboard.app"
    cp -R "$APP" "$DEST/"
    echo "installed $DEST/Switchboard.app"
    open "$DEST/Switchboard.app"
fi
