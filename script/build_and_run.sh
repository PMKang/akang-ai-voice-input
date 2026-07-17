#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AkangVoiceInput"
DISPLAY_NAME="Noboard · 自在说"
BUNDLE_ID="com.akang.ai-voice-input"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${AKANG_APP_VERSION:-1.1.1}"
BUILD_TIMESTAMP="${AKANG_BUILD_TIMESTAMP:-$(date '+%m%d%H%M%S')}"
BUILD_CONFIGURATION="${AKANG_BUILD_CONFIGURATION:-debug}"
HIDE_EXPRESSION_STYLE="${AKANG_HIDE_EXPRESSION_STYLE:-NO}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi
for icon_theme in Blue Violet Coral; do
  icon_source="$ROOT_DIR/Resources/BrandIcons/NoboardIcon${icon_theme}.png"
  if [[ -f "$icon_source" ]]; then
    cp "$icon_source" "$APP_RESOURCES/NoboardIcon${icon_theme}.png"
  fi
done
if [[ -f "$ROOT_DIR/Resources/OfficialAccountQR.jpg" ]]; then
  cp "$ROOT_DIR/Resources/OfficialAccountQR.jpg" "$APP_RESOURCES/OfficialAccountQR.jpg"
fi
if [[ -f "$ROOT_DIR/Resources/VideoChannelQR.jpg" ]]; then
  cp "$ROOT_DIR/Resources/VideoChannelQR.jpg" "$APP_RESOURCES/VideoChannelQR.jpg"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_TIMESTAMP</string>
  <key>AkangBuildTimestamp</key>
  <string>$BUILD_TIMESTAMP</string>
  <key>AkangHideExpressionStyle</key>
  <string>$HIDE_EXPRESSION_STYLE</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Noboard · 自在说需要使用麦克风，将您的语音转换为文字。</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    echo "$DISPLAY_NAME 已构建：$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$DISPLAY_NAME 已启动：$APP_BUNDLE"
    ;;
  *)
    echo "用法：$0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
