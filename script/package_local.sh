#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---install}"
APP_VERSION="1.3.0"
BUILD_TIMESTAMP="${AKANG_BUILD_TIMESTAMP:-$(date '+%m%d%H%M%S')}"
SOURCE_APP="$ROOT_DIR/dist/AkangVoiceInput.app"
SOURCE_BINARY="$SOURCE_APP/Contents/MacOS/AkangVoiceInput"
SOURCE_INFO_PLIST="$SOURCE_APP/Contents/Info.plist"
# 默认安装到系统“应用程序”目录，避免与 ~/Applications 的同名副本混淆。
INSTALL_DIR="${AKANG_INSTALL_DIR:-/Applications}"
INSTALL_APP="$INSTALL_DIR/Noboard · 自在说.app"
ARCHIVE_DIR="$ROOT_DIR/release"
ARCHIVE_PATH="$ARCHIVE_DIR/AkangVoiceInput-v${APP_VERSION}-${BUILD_TIMESTAMP}-macos.zip"
DMG_PATH="$ARCHIVE_DIR/AkangVoiceInput-v${APP_VERSION}-${BUILD_TIMESTAMP}-macos.dmg"

if [[ "$MODE" != "--install" && "$MODE" != "--package-only" ]]; then
  echo "用法：$0 [--install|--package-only]" >&2
  exit 2
fi

cd "$ROOT_DIR"
AKANG_APP_VERSION="$APP_VERSION" \
AKANG_BUILD_CONFIGURATION=release \
AKANG_BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
  ./script/build_and_run.sh --build-only

codesign --verify --deep --strict "$SOURCE_APP"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO_PLIST")"
if [[ "$ACTUAL_VERSION" != "$APP_VERSION" ]]; then
  echo "App 版本校验失败：期望 $APP_VERSION，实际 $ACTUAL_VERSION" >&2
  exit 1
fi

BUILT_ARCHITECTURES="$(lipo -archs "$SOURCE_BINARY")"
for required_architecture in arm64 x86_64; do
  if [[ " $BUILT_ARCHITECTURES " != *" $required_architecture "* ]]; then
    echo "Universal 架构校验失败：缺少 $required_architecture（实际：$BUILT_ARCHITECTURES）" >&2
    exit 1
  fi
done

mkdir -p "$ARCHIVE_DIR"
ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$SOURCE_APP" "$ARCHIVE_PATH"
./script/create_dmg.sh "$SOURCE_APP" "$DMG_PATH" "$APP_VERSION"
unzip -tqq "$ARCHIVE_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

echo "产物校验通过：v$ACTUAL_VERSION · $BUILT_ARCHITECTURES"
echo "自动更新包：$ARCHIVE_PATH"
echo "首次安装包：$DMG_PATH"

if [[ "$MODE" == "--package-only" ]]; then
  exit 0
fi

mkdir -p "$INSTALL_DIR"
pkill -x AkangVoiceInput >/dev/null 2>&1 || true
rm -rf "$INSTALL_APP"
ditto "$SOURCE_APP" "$INSTALL_APP"
open -n "$INSTALL_APP"

echo "已安装：$INSTALL_APP"
