#!/bin/bash
# Packages the SPM binary as a real .app bundle. A bare executable launched from
# a terminal is not treated the same as a bundled app by the window server, which
# matters for the lock-screen overlay.
#
#   ./build_app.sh            build into ./build
#   ./build_app.sh --install  build and install into /Applications, then relaunch
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DynamicIslandMac.app"
CONFIG="release"
INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        debug|release) CONFIG="$arg" ;;
    esac
done

swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$ROOT/.build/$CONFIG/DynamicIslandMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIslandMac"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# System-wide Now Playing (browsers, any media app) goes through the vendored
# mediaremote-adapter: a small framework that /usr/bin/perl loads, because
# MediaRemote no longer answers ad-hoc-signed apps. See Vendor/mediaremote-adapter.
ADAPTER="$ROOT/Vendor/mediaremote-adapter"
FW="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$FW/Versions/A/Resources"
clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -fobjc-arc -fvisibility=default -O2 \
    -I"$ADAPTER/include" -I"$ADAPTER/src" \
    "$ADAPTER"/src/adapter/*.m "$ADAPTER"/src/private/*.m "$ADAPTER"/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$FW/Versions/A/MediaRemoteAdapter"
cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.MediaRemoteAdapter</string>
    <key>CFBundleName</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundleExecutable</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
</dict>
</plist>
PLIST
ln -sfn A "$FW/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FW/Resources"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Dynamic Island</string>
    <key>CFBundleDisplayName</key>
    <string>Dynamic Island</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikita.dynamicislandmac</string>
    <key>CFBundleExecutable</key>
    <string>DynamicIslandMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Чтобы показывать текущий трек, приложению нужен доступ к Spotify и Music.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Чтобы показывать события из Календаря в острове, приложению нужен доступ к календарю.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Чтобы показывать напоминания и отмечать их выполненными, приложению нужен доступ к Напоминаниям.</string>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"

if [ "$INSTALL" = true ]; then
    pkill -f "/Applications/Dynamic Island.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/Dynamic Island.app"
    cp -R "$APP" "/Applications/Dynamic Island.app"
    # Nudge Launch Services so the new icon and name show up straight away.
    touch "/Applications/Dynamic Island.app"
    echo "installed: /Applications/Dynamic Island.app"
    open "/Applications/Dynamic Island.app"
else
    echo "built: $APP"
fi
