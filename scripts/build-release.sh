#!/bin/bash
# Release ビルド → 「Ttemp Signing」で安定署名 → DMG、ZIP、appcast.xml を作る。
# ローカルでも CI（.github/workflows/ci.yml）でも同じ手順を通すための共通スクリプト。
# 通常のリリースは日英ノートを含めて main へ push すると CI が行う（docs/SIGNING.md）。
#
# 環境変数（ローカルでもTTEMP_PREVIOUS_RELEASEは必須）:
#   TTEMP_PREVIOUS_RELEASE 最新の公開済みGitHub Release tag。ノートの差分基準
#   TTEMP_SIGN_IDENTITY  署名 identity（既定: Ttemp Signing）
#   TTEMP_VERSION        確認用の表示version（省略時はmajor.minor.<commit count>）
#   TTEMP_BUILD          確認用のbuild番号（省略時はcommit count）
#   TTEMP_ED_KEY_FILE    Sparkle EdDSA 秘密鍵ファイル。未設定ならログインキーチェーンの鍵を使う
#   TTEMP_KEYCHAIN       署名に使うキーチェーン。未設定なら既定の検索リスト

set -euo pipefail
cd "$(dirname "$0")/.."

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "tracked fileに未コミット変更があります。release前にcommitしてください。" >&2
    exit 1
fi
SOURCE_REVISION=$(git rev-parse HEAD)
if [ -z "${TTEMP_PREVIOUS_RELEASE:-}" ]; then
    echo "TTEMP_PREVIOUS_RELEASEに最新の公開済みRelease tagを指定してください（docs/SIGNING.md）。" >&2
    exit 1
fi
VERSION="${TTEMP_VERSION:-$(python3 scripts/release-notes.py version)}"
BUILD="${TTEMP_BUILD:-${VERSION##*.}}"
if [ "$BUILD" != "${VERSION##*.}" ]; then
    echo "TTEMP_BUILDがversion内のcommit countと一致しません。" >&2
    exit 1
fi
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-release.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
python3 scripts/release-notes.py render --since "$TTEMP_PREVIOUS_RELEASE" --version "$VERSION" \
    > "$WORK_DIR/release-notes.md"

IDENTITY="${TTEMP_SIGN_IDENTITY:-Ttemp Signing}"

if [ -n "${TTEMP_KEYCHAIN:-}" ] && [[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    # CIの自己署名証明書はheadless trust設定を避けるため、fingerprintで直接選択する。
    if ! security find-certificate -a -Z "$TTEMP_KEYCHAIN" | grep -Fi "SHA-1 hash: $IDENTITY" >/dev/null; then
        echo "コード署名 certificate '$IDENTITY' が $TTEMP_KEYCHAIN に見つかりません。" >&2
        exit 1
    fi
elif ! security find-identity -v -p codesigning ${TTEMP_KEYCHAIN:+"$TTEMP_KEYCHAIN"} | grep -F "\"$IDENTITY\"" >/dev/null; then
    echo "コード署名 identity '$IDENTITY' が見つかりません。" >&2
    echo "先に ./scripts/setup-release-keys.sh を実行してください。" >&2
    exit 1
fi

VERIFY_MODE=$(python3 scripts/diagnostic-launch.py distribution-mode)

echo "==> プロジェクト生成とビルド"
xcodegen generate
XCODE_ARGS=(
    -project Ttemp.xcodeproj -scheme Ttemp -configuration Release
    -destination generic/platform=macOS
    -derivedDataPath build/DerivedData
    CODE_SIGN_IDENTITY="$IDENTITY"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$BUILD"
)
[ -n "${TTEMP_KEYCHAIN:-}" ] && XCODE_ARGS+=(OTHER_CODE_SIGN_FLAGS="--keychain $TTEMP_KEYCHAIN")
xcodebuild "${XCODE_ARGS[@]}" build

APP="build/DerivedData/Build/Products/Release/Ttemp.app"

echo "==> helperを含む安定署名とlibrary constraint"
TTEMP_SIGN_IDENTITY="$IDENTITY" ./scripts/sign-app.sh "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = com.am921.ttemp
./scripts/verify-app.sh "$VERIFY_MODE" "$APP"

echo "==> dist/ へ配置"
mkdir -p dist
rm -rf dist/Ttemp.app dist/Ttemp.dmg dist/Ttemp.zip dist/appcast.xml dist/SHA256SUMS
cp -R "$APP" dist/
NOTES_PATH="dist/release-notes-v$VERSION.md"
cp "$WORK_DIR/release-notes.md" "$NOTES_PATH"
ditto -c -k --keepParent dist/Ttemp.app dist/Ttemp.zip
ditto -x -k dist/Ttemp.zip "$WORK_DIR/unpacked"
./scripts/verify-app.sh "$VERIFY_MODE" "$WORK_DIR/unpacked/Ttemp.app"

APP_VERSION=$(defaults read "$PWD/dist/Ttemp.app/Contents/Info" CFBundleShortVersionString)
APP_BUILD=$(defaults read "$PWD/dist/Ttemp.app/Contents/Info" CFBundleVersion)
if [ "$APP_VERSION" != "$VERSION" ] || [ "$APP_BUILD" != "$BUILD" ]; then
    echo "ビルドしたappのversion/buildがリリースノートと一致しません。" >&2
    exit 1
fi

echo "==> 初回インストール用DMGを生成"
./scripts/create-dmg.sh dist/Ttemp.app dist/Ttemp.dmg

echo "==> appcast.xml を生成（EdDSA 署名）"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "$SPARKLE_BIN/sign_update が見つかりません。SPM の解決が必要です:" >&2
    echo "  xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -derivedDataPath build/DerivedData -resolvePackageDependencies" >&2
    exit 1
fi
if [ -n "${TTEMP_ED_KEY_FILE:-}" ]; then
    ED_PARAMS=$("$SPARKLE_BIN/sign_update" --ed-key-file "$TTEMP_ED_KEY_FILE" dist/Ttemp.zip)
else
    ED_PARAMS=$("$SPARKLE_BIN/sign_update" dist/Ttemp.zip)
fi
ED_SIGNATURE=$(printf '%s\n' "$ED_PARAMS" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
ED_LENGTH=$(printf '%s\n' "$ED_PARAMS" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
ACTUAL_LENGTH=$(stat -f '%z' dist/Ttemp.zip)
if [ -z "$ED_SIGNATURE" ] || [ "$ED_LENGTH" != "$ACTUAL_LENGTH" ]; then
    echo "Sparkle signature metadata が不正です。" >&2
    exit 1
fi
DOWNLOAD_URL="https://github.com/RioRio-do/ttemp/releases/download/v$VERSION/Ttemp.zip"
PUB_DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Ttemp</title>
        <item>
            <title>Ttemp $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL"
                       sparkle:version="$BUILD"
                       sparkle:shortVersionString="$VERSION"
                       $ED_PARAMS
                       type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

xmllint --noout dist/appcast.xml
echo "==> Sparkle archive EdDSA 署名の検証"
if [ -n "${TTEMP_ED_KEY_FILE:-}" ]; then
    "$SPARKLE_BIN/sign_update" --verify --ed-key-file "$TTEMP_ED_KEY_FILE" \
        dist/Ttemp.zip "$ED_SIGNATURE"
else
    "$SPARKLE_BIN/sign_update" --verify dist/Ttemp.zip "$ED_SIGNATURE"
fi

echo "==> appcast自体をEdDSA署名"
if [ -n "${TTEMP_ED_KEY_FILE:-}" ]; then
    "$SPARKLE_BIN/sign_update" --ed-key-file "$TTEMP_ED_KEY_FILE" dist/appcast.xml
else
    "$SPARKLE_BIN/sign_update" dist/appcast.xml
fi
xmllint --noout dist/appcast.xml
if [ -n "${TTEMP_ED_KEY_FILE:-}" ]; then
    "$SPARKLE_BIN/sign_update" --verify --ed-key-file "$TTEMP_ED_KEY_FILE" dist/appcast.xml
else
    "$SPARKLE_BIN/sign_update" --verify dist/appcast.xml
fi

echo "==> 公開assetのSHA-256を記録"
xcrun swift -module-cache-path build/verification-module-cache \
    scripts/verify-update.swift dist/Ttemp.app dist/Ttemp.zip dist/appcast.xml
(cd dist && shasum -a 256 Ttemp.dmg Ttemp.zip appcast.xml > SHA256SUMS)

echo "完了: dist/Ttemp.dmg + dist/Ttemp.zip + dist/appcast.xml + dist/SHA256SUMS (Ttemp $VERSION, build $BUILD, identity: $IDENTITY)"
echo "リリースノート: $NOTES_PATH"
if [ "$VERIFY_MODE" = --static-only ]; then
    echo '実起動と画面表示は未確認です。公開は本番appの実起動を検証するCIで行ってください。'
else
    echo "手動でリリースする場合: gh release create \"v$VERSION\" dist/Ttemp.dmg dist/Ttemp.zip dist/appcast.xml dist/SHA256SUMS --target \"$SOURCE_REVISION\" --title \"Ttemp $VERSION\" --notes-file \"$NOTES_PATH\""
fi
