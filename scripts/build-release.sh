#!/bin/bash
# Release ビルドを「Ttemp Signing」（自己署名証明書）で安定署名し、dist/ に zip を出し、
# Sparkle 用の appcast.xml をリポジトリ直下に書き出す。
# 証明書がまだ無ければ、先に scripts/create-signing-cert.sh を実行すること。
#
# リリース手順（docs/SIGNING.md）:
#   1. project.yml の MARKETING_VERSION と CURRENT_PROJECT_VERSION を上げる
#   2. このスクリプトを実行
#   3. appcast.xml をコミットして push（SUFeedURL は main の appcast.xml を見る）
#   4. gh release create "v<版>" dist/Ttemp.zip

set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${TTEMP_SIGN_IDENTITY:-Ttemp Signing}"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "コード署名 identity '$IDENTITY' が見つかりません。" >&2
    echo "先に ./scripts/create-signing-cert.sh を実行してください。" >&2
    exit 1
fi

echo "==> プロジェクト生成とビルド"
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    build

APP="build/DerivedData/Build/Products/Release/Ttemp.app"

echo "==> 署名の検証"
codesign --verify --strict --verbose=2 "$APP"

echo "==> dist/ へ配置"
mkdir -p dist
rm -rf dist/Ttemp.app dist/Ttemp.zip
cp -R "$APP" dist/
ditto -c -k --keepParent dist/Ttemp.app dist/Ttemp.zip

VERSION=$(defaults read "$PWD/dist/Ttemp.app/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$PWD/dist/Ttemp.app/Contents/Info" CFBundleVersion)

echo "==> appcast.xml を生成（EdDSA 署名。鍵はログインキーチェーンの generate_keys 産）"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "$SPARKLE_BIN/sign_update が見つかりません。ビルドで SPM の解決が済んでいるはずですが、" >&2
    echo "見つからない場合は: xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -derivedDataPath build/DerivedData -resolvePackageDependencies" >&2
    exit 1
fi
ED_PARAMS=$("$SPARKLE_BIN/sign_update" dist/Ttemp.zip)   # sparkle:edSignature="…" length="…"
DOWNLOAD_URL="https://github.com/RioRio-do/ttemp/releases/download/v$VERSION/Ttemp.zip"
PUB_DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")

cat > appcast.xml <<EOF
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

echo "完了: dist/Ttemp.zip (Ttemp $VERSION, build $BUILD, identity: $IDENTITY)"
echo
echo "次にやること:"
echo "  git add appcast.xml && git commit -m \"v$VERSION の appcast\" && git push"
echo "  gh release create \"v$VERSION\" dist/Ttemp.zip --title \"Ttemp $VERSION\""
echo "（appcast は更新の存在を CFBundleVersion=$BUILD の大小で判定する。リリースごとに必ず上げること）"
