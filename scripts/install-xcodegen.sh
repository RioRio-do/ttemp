#!/bin/bash
# CI で使う XcodeGen を、公式リリースassetの固定version + SHA-256で導入する。

set -euo pipefail

VERSION="2.46.0"
ARCHIVE_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
ARCHIVE_URL="https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
INSTALL_ROOT="${1:-build/tools}"
INSTALL_DIRECTORY="$INSTALL_ROOT/xcodegen-$VERSION"
BIN_DIRECTORY="$INSTALL_DIRECTORY/xcodegen/bin"
XCODEGEN="$BIN_DIRECTORY/xcodegen"

if [ -x "$XCODEGEN" ]; then
    [ "$($XCODEGEN --version)" = "Version: $VERSION" ] || {
        echo "既存のXcodeGenが固定versionと一致しません: $XCODEGEN" >&2
        exit 1
    }
    printf '%s\n' "$BIN_DIRECTORY"
    exit 0
fi

if [ -e "$INSTALL_DIRECTORY" ]; then
    echo "不完全なXcodeGen配置先が既に存在します: $INSTALL_DIRECTORY" >&2
    exit 1
fi

mkdir -p "$INSTALL_ROOT"
TEMP_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-xcodegen.XXXXXX")
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT
ARCHIVE="$TEMP_DIRECTORY/xcodegen.zip"

echo "==> XcodeGen $VERSION を取得" >&2
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$ARCHIVE" "$ARCHIVE_URL"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" | shasum -a 256 --check

mkdir "$INSTALL_DIRECTORY"
ditto -x -k "$ARCHIVE" "$INSTALL_DIRECTORY"
if [ ! -x "$XCODEGEN" ] || [ "$($XCODEGEN --version)" != "Version: $VERSION" ]; then
    echo "XcodeGen $VERSION の展開結果を検証できませんでした。" >&2
    exit 1
fi

printf '%s\n' "$BIN_DIRECTORY"
