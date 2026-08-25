#!/bin/bash
# Release ビルドを「Ttemp Signing」（自己署名証明書）で安定署名し、dist/ に zip を出す。
# 証明書がまだ無ければ、先に scripts/create-signing-cert.sh を実行すること。

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
echo "完了: dist/Ttemp.zip (Ttemp $VERSION, identity: $IDENTITY)"
