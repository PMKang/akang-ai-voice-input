#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "用法：$0 <App 路径> <输出 DMG 路径> <版本号>" >&2
  exit 2
fi

SOURCE_APP="$1"
OUTPUT_DMG="$2"
APP_VERSION="$3"
APP_FILENAME="Noboard · 自在说.app"
VOLUME_NAME="Noboard 自在说 v${APP_VERSION}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/DMGModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/DMGModuleCache"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "找不到待打包的 App：$SOURCE_APP" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/noboard-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
MOUNT_DIR="$WORK_DIR/mount"
RW_IMAGE="$WORK_DIR/noboard-rw.dmg"
MOUNTED=0

cleanup() {
  if [[ $MOUNTED -eq 1 ]]; then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR" "$BACKGROUND_DIR" "$MOUNT_DIR" "$(dirname "$OUTPUT_DMG")"
ditto "$SOURCE_APP" "$STAGING_DIR/$APP_FILENAME"
ln -s /Applications "$STAGING_DIR/Applications"
swift "$ROOT_DIR/script/generate_dmg_background.swift" \
  "$BACKGROUND_DIR/background.png" \
  "$APP_VERSION"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_IMAGE" >/dev/null

hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" \
  "$RW_IMAGE" >/dev/null
MOUNTED=1

osascript - "$MOUNT_DIR" "$APP_FILENAME" <<'APPLESCRIPT'
on run arguments
  set mountPath to item 1 of arguments
  set appFilename to item 2 of arguments
  set diskFolder to POSIX file mountPath as alias
  set backgroundFile to POSIX file (mountPath & "/.background/background.png") as alias

  tell application "Finder"
    open diskFolder
    delay 1
    tell front Finder window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set pathbar visible to false
      set bounds to {180, 140, 840, 560}
    end tell

    tell icon view options of front Finder window
      set arrangement to not arranged
      set icon size to 104
      set text size to 13
      set background picture to backgroundFile
    end tell

    set position of item appFilename of diskFolder to {170, 218}
    set position of item "Applications" of diskFolder to {490, 218}
    update diskFolder without registering applications
    delay 2
    close front Finder window
  end tell
end run
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

rm -f "$OUTPUT_DMG"
hdiutil convert \
  "$RW_IMAGE" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

echo "DMG 安装包：$OUTPUT_DMG"
