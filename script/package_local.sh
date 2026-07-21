#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="1.2.3"
BUILD_TIMESTAMP="${AKANG_BUILD_TIMESTAMP:-$(date '+%m%d%H%M%S')}"
PACKAGE_SUFFIX="${AKANG_PACKAGE_SUFFIX:-macos}"
SOURCE_APP="$ROOT_DIR/dist/AkangVoiceInput.app"
# 默认安装到系统“应用程序”目录，避免与 ~/Applications 的同名副本混淆。
INSTALL_DIR="${AKANG_INSTALL_DIR:-/Applications}"
ARCHIVE_DIR="$ROOT_DIR/release"
ARCHIVE_PATH="$ARCHIVE_DIR/AkangVoiceInput-v${APP_VERSION}-${BUILD_TIMESTAMP}-${PACKAGE_SUFFIX}.zip"
APP_ICON_DEV_BADGE="${AKANG_APP_ICON_DEV_BADGE:-NO}"

if [[ "$PACKAGE_SUFFIX" == *"local-test"* ]]; then
  APP_ICON_DEV_BADGE="YES"
  INSTALL_APP="${AKANG_INSTALL_APP:-$INSTALL_DIR/Noboard · 自在说 Dev.app}"
else
  INSTALL_APP="${AKANG_INSTALL_APP:-$INSTALL_DIR/Noboard · 自在说.app}"
fi

cd "$ROOT_DIR"
AKANG_BUILD_CONFIGURATION=release \
AKANG_BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
AKANG_APP_ICON_DEV_BADGE="$APP_ICON_DEV_BADGE" \
AKANG_DEVELOPMENT_BUILD="$APP_ICON_DEV_BADGE" \
./script/build_and_run.sh --build-only

mkdir -p "$ARCHIVE_DIR"
mkdir -p "$INSTALL_DIR"
ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$SOURCE_APP" "$ARCHIVE_PATH"

pkill -x AkangVoiceInput >/dev/null 2>&1 || true
rm -rf "$INSTALL_APP"
ditto "$SOURCE_APP" "$INSTALL_APP"
open -n "$INSTALL_APP"

echo "已安装：$INSTALL_APP"
echo "测试包：$ARCHIVE_PATH"
