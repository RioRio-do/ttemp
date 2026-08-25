#!/bin/bash
# 署名済み Ttemp.app から、Applications へのドラッグ導線を持つ配布用 DMG を作る。

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 Ttemp.app OUTPUT.dmg" >&2
    exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_INPUT=$1
OUTPUT_INPUT=$2

if [ ! -d "$APP_INPUT" ] || [ "$(basename "$APP_INPUT")" != "Ttemp.app" ]; then
    echo "署名済みの Ttemp.app を指定してください: $APP_INPUT" >&2
    exit 1
fi
if [[ "$OUTPUT_INPUT" != *.dmg ]]; then
    echo "出力ファイルは .dmg で終わる必要があります: $OUTPUT_INPUT" >&2
    exit 1
fi

APP_DIR=$(cd "$(dirname "$APP_INPUT")" && pwd)
OUTPUT_DIR=$(cd "$(dirname "$OUTPUT_INPUT")" && pwd)
APP_PATH="$APP_DIR/$(basename "$APP_INPUT")"
OUTPUT_DMG="$OUTPUT_DIR/$(basename "$OUTPUT_INPUT")"
VOLUME_NAME=Ttemp
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-dmg.XXXXXX")
STAGING_DIR="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/Ttemp-rw.dmg"
MOUNTED_DEVICE=

cleanup() {
    trap - EXIT INT TERM HUP
    if [ -n "$MOUNTED_DEVICE" ]; then
        detach_dmg "$MOUNTED_DEVICE" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM HUP

detach_dmg() {
    local device=$1
    if hdiutil detach "$device" -quiet; then
        return 0
    fi
    sleep 2
    hdiutil detach "$device" -force -quiet
}

mkdir -p "$STAGING_DIR/.background"
ditto "$APP_PATH" "$STAGING_DIR/Ttemp.app"
ln -s /Applications "$STAGING_DIR/Applications"
xcrun swift -module-cache-path "$WORK_DIR/swift-module-cache" \
    "$SCRIPT_DIR/render-dmg-background.swift" \
    "$STAGING_DIR/.background/background.png"

echo "==> 装飾用の読み書き可能DMGを作成"
hdiutil create -quiet -ov -format UDRW -fs HFS+ \
    -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" "$RW_DMG"

ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
MOUNTED_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' 'NR == 1 { gsub(/[[:space:]]/, "", $1); print $1 }')
MOUNT_DIR=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF; exit }')
if [[ ! "$MOUNTED_DEVICE" =~ ^/dev/disk[0-9]+$ ]] || \
   [[ "$MOUNT_DIR" != /Volumes/Ttemp* ]]; then
    echo "DMG のマウント先を判定できませんでした。" >&2
    exit 1
fi

xcrun SetFile -a V "$MOUNT_DIR/.background"
mkdir -p "$MOUNT_DIR/.fseventsd"
touch "$MOUNT_DIR/.fseventsd/no_log"
xcrun SetFile -a V "$MOUNT_DIR/.fseventsd"

layout_dmg() {
    osascript - "$MOUNT_DIR" <<'APPLESCRIPT'
on run argv
    set mountPath to item 1 of argv
    set volumeName to do shell script "/usr/bin/basename " & quoted form of mountPath

    with timeout of 30 seconds
        tell application "Finder"
            tell disk volumeName
                open
                set installerWindow to container window
                set current view of installerWindow to icon view
                set toolbar visible of installerWindow to false
                set statusbar visible of installerWindow to false
                set pathbar visible of installerWindow to false
                set bounds of installerWindow to {100, 100, 760, 500}

                set viewOptions to icon view options of installerWindow
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 104
                set text size of viewOptions to 13
                set background picture of viewOptions to file ".background:background.png"

                set position of item "Ttemp.app" of installerWindow to {165, 205}
                set position of item "Applications" of installerWindow to {495, 205}

                update without registering applications
                delay 1
                close installerWindow
            end tell
        end tell
    end timeout
end run
APPLESCRIPT
}

echo "==> Finder表示を整える"
if ! layout_dmg; then
    echo "Finderが準備できなかったためDMGレイアウトを再試行します。" >&2
    sleep 2
    layout_dmg
fi

# 読み書きマウント中にmacOSが作る管理ディレクトリは配布物へ含めない。
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Spotlight-V100" \
    "$MOUNT_DIR/.TemporaryItems" "$MOUNT_DIR/.Trashes"
sync
detach_dmg "$MOUNTED_DEVICE"
MOUNTED_DEVICE=

rm -f "$OUTPUT_DMG"
hdiutil convert "$RW_DMG" -quiet -ov -format UDZO -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG"

echo "==> DMGの構造と署名済みappを検証"
hdiutil verify "$OUTPUT_DMG" >/dev/null
VERIFY_OUTPUT=$(hdiutil attach -readonly -nobrowse -noverify -noautoopen "$OUTPUT_DMG")
MOUNTED_DEVICE=$(printf '%s\n' "$VERIFY_OUTPUT" | awk -F '\t' 'NR == 1 { gsub(/[[:space:]]/, "", $1); print $1 }')
VERIFY_MOUNT=$(printf '%s\n' "$VERIFY_OUTPUT" | awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF; exit }')
if [[ ! "$MOUNTED_DEVICE" =~ ^/dev/disk[0-9]+$ ]] || [ -z "$VERIFY_MOUNT" ]; then
    echo "完成したDMGのマウント先を判定できませんでした。" >&2
    exit 1
fi

test -d "$VERIFY_MOUNT/Ttemp.app"
test -L "$VERIFY_MOUNT/Applications"
test "$(readlink "$VERIFY_MOUNT/Applications")" = /Applications
test -f "$VERIFY_MOUNT/.background/background.png"
test -f "$VERIFY_MOUNT/.DS_Store"
test ! -e "$VERIFY_MOUNT/.fseventsd"
test ! -e "$VERIFY_MOUNT/.Spotlight-V100"
codesign --verify --deep --strict --verbose=2 "$VERIFY_MOUNT/Ttemp.app"

detach_dmg "$MOUNTED_DEVICE"
MOUNTED_DEVICE=
echo "DMG検証完了: $OUTPUT_DMG"
