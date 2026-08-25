#!/bin/bash
# 自己署名のコード署名証明書「Ttemp Signing」を作り、ログインキーチェーンに入れる。
#
# なぜ必要か:
#   ad-hoc 署名（CODE_SIGN_IDENTITY: "-"）はビルドのたびに署名の同一性が変わるため、
#   macOS の TCC（入力監視の許可）がビルドごとにリセットされる。
#   自己署名でも「同じ証明書」で署名し続ければ designated requirement が安定し、
#   再ビルド・更新後も許可が引き継がれる。
#
# 使い方:
#   ./scripts/create-signing-cert.sh
#   途中でキーチェーンの信頼設定の確認（macOS のパスワード入力）が出る。
#   初回の codesign 実行時に「鍵へのアクセス」の確認が出たら「常に許可」を選ぶ。

set -euo pipefail

IDENTITY="Ttemp Signing"
DAYS=3650
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "証明書 '$IDENTITY' は既にキーチェーンにあります。作り直す場合は先に削除してください:" >&2
    echo "  security delete-certificate -c \"$IDENTITY\" \"$KEYCHAIN\"" >&2
    exit 1
fi

echo "==> 証明書と秘密鍵を生成 (有効期間 ${DAYS} 日)"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORKDIR/key.pem" \
    -out "$WORKDIR/cert.pem" \
    -days "$DAYS" \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE"

echo "==> ログインキーチェーンへ取り込み"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" \
    -in "$WORKDIR/cert.pem" \
    -name "$IDENTITY" \
    -passout pass:ttemp \
    -out "$WORKDIR/ttemp.p12"
security import "$WORKDIR/ttemp.p12" -k "$KEYCHAIN" -P ttemp -T /usr/bin/codesign

echo "==> 証明書を『コード署名で信頼』に設定（パスワードの確認が出ます）"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo "==> 確認"
security find-identity -v -p codesigning | grep "$IDENTITY" || {
    echo "identity が有効になっていません。キーチェーンアクセス.app で '$IDENTITY' の信頼設定を確認してください。" >&2
    exit 1
}

echo "完了。scripts/build-release.sh がこの identity で署名します。"
echo "注意: ad-hoc 署名のビルドからこの証明書に切り替えた直後の1回だけ、入力監視の再許可が必要です。"
