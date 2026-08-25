#!/bin/bash
# リリースに使う鍵一式を用意し、GitHub Actions のリポジトリシークレットへ登録する。
#
# やること:
#   1. コード署名証明書「Ttemp Signing」を signing/ に保存してログインキーチェーンへ
#      取り込む。既存 .p12 は証明書を変えずApple Security互換形式へ再梱包する
#   2. Sparkle EdDSA 秘密鍵をキーチェーンから signing/ にエクスポート
#   3. 3つのシークレットを gh で登録:
#        SIGNING_CERT_P12       … .p12 の base64
#        SIGNING_CERT_PASSWORD  … .p12 のパスワード
#        SPARKLE_ED_PRIVATE_KEY … Sparkle EdDSA 秘密鍵
#
# 証明書の新規作成時だけ、配布済みアプリの TCC 許可（入力監視）と自分のマシンの
# 許可が一度リセットされる。既存 .p12 の再梱包ではidentityは変わらない。
# signing/ の中身はgit管理外なので、パスワードマネージャ等に必ずバックアップすること。
#
# 途中でキーチェーンの確認ダイアログ（信頼設定・鍵アクセス）が出たら許可すること。

set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

IDENTITY="Ttemp Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OUT_DIR="signing"
REPO="RioRio-do/ttemp"
DAYS=3650

TTEMP_KEY_WORK_DIR=$(mktemp -d)
cleanup() {
    # 秘密鍵を含む一時 PEM を必ず消す。mktemp で作った専用ディレクトリ以外は触らない。
    if [ -n "${TTEMP_KEY_WORK_DIR:-}" ] && [ -d "$TTEMP_KEY_WORK_DIR" ]; then
        rm -rf "$TTEMP_KEY_WORK_DIR"
    fi
}
trap cleanup EXIT

command -v gh >/dev/null || { echo "gh (GitHub CLI) が必要です: brew install gh" >&2; exit 1; }
gh auth status >/dev/null || { echo "gh auth login でログインしてください" >&2; exit 1; }

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# --- 1. コード署名証明書 ---

P12="$OUT_DIR/ttemp-signing.p12"
P12_PASSWORD_FILE="$OUT_DIR/ttemp-signing.p12.password"

if { [ -e "$P12" ] && [ ! -e "$P12_PASSWORD_FILE" ]; } ||
   { [ ! -e "$P12" ] && [ -e "$P12_PASSWORD_FILE" ]; }; then
    echo "$P12 と $P12_PASSWORD_FILE は必ず対で必要です。片方だけの状態ではidentityを作り直しません。" >&2
    exit 1
fi
if { [ -e "$P12" ] && [ ! -f "$P12" ]; } ||
   { [ -e "$P12_PASSWORD_FILE" ] && [ ! -f "$P12_PASSWORD_FILE" ]; }; then
    echo "$P12 と $P12_PASSWORD_FILE は通常ファイルである必要があります。" >&2
    exit 1
fi

p12_certificate_fingerprint() {
    openssl pkcs12 -in "$1" -passin "file:$P12_PASSWORD_FILE" -clcerts -nokeys |
        openssl x509 -noout -fingerprint -sha256
}

p12_certificate_sha1() {
    openssl pkcs12 -in "$1" -passin "file:$P12_PASSWORD_FILE" -clcerts -nokeys |
        openssl x509 -noout -fingerprint -sha1 |
        sed 's/^.*=//; s/://g'
}

keychain_identity_sha1() {
    security find-identity -v -p codesigning "$KEYCHAIN" |
        awk -v identity="$IDENTITY" 'index($0, "\"" identity "\"") { print $2; exit }'
}

# Apple Security.framework は OS バージョンによって SHA-256 MAC の PKCS#12 を
# `wrong password?` と誤報して拒否する。証明書・秘密鍵自体は変えず、CI の最小対象
# macOS 15 でも読める SHA-1 MAC / 3DES PBE のコンテナへ詰め直す。
# P12 は GitHub Secret で暗号化保管し、パスワードもランダムなため、ここでの legacy
# algorithm は transport compatibility のためだけに使う。
repack_p12_for_apple_security() {
    local source_fingerprint repacked_fingerprint
    local identity_pem="$TTEMP_KEY_WORK_DIR/identity.pem"
    local compatible_p12="$TTEMP_KEY_WORK_DIR/ttemp-signing-compatible.p12"

    # 既存ファイルとpasswordが不一致なら、上書きする前に明示的に停止する。
    openssl pkcs12 -in "$P12" -passin "file:$P12_PASSWORD_FILE" -noout
    source_fingerprint=$(p12_certificate_fingerprint "$P12")

    openssl pkcs12 -in "$P12" -passin "file:$P12_PASSWORD_FILE" \
        -nodes -out "$identity_pem"
    openssl pkcs12 -export \
        -inkey "$identity_pem" \
        -in "$identity_pem" \
        -name "$IDENTITY" \
        -keypbe PBE-SHA1-3DES \
        -certpbe PBE-SHA1-3DES \
        -macalg sha1 \
        -passout "file:$P12_PASSWORD_FILE" \
        -out "$compatible_p12"

    # 再梱包後もpasswordで読め、同じcertificate identityであることを確認してから置換する。
    openssl pkcs12 -in "$compatible_p12" -passin "file:$P12_PASSWORD_FILE" -noout
    repacked_fingerprint=$(p12_certificate_fingerprint "$compatible_p12")
    if [ "$source_fingerprint" != "$repacked_fingerprint" ]; then
        echo "PKCS#12 の再梱包で証明書fingerprintが変化したため中止します。" >&2
        exit 1
    fi

    mv "$compatible_p12" "$P12"
    chmod 600 "$P12" "$P12_PASSWORD_FILE"
    rm -f "$identity_pem"
    echo "==> Apple Security互換PKCS#12へ再梱包（certificate identityは維持）"
}

if [ -f "$P12" ] && [ -f "$P12_PASSWORD_FILE" ]; then
    echo "==> 既存の $P12 を使う（作り直しはしない）"
else
    if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
        echo "==> 既存の '$IDENTITY' identity を削除して作り直す"
        echo "    （旧証明書は .p12 が残っておらず CI と共有できないため。"
        echo "      この影響で、次のビルドで入力監視の再許可が一度だけ必要になる）"
        security delete-identity -c "$IDENTITY" "$KEYCHAIN"
    fi

    echo "==> 証明書と秘密鍵を生成（有効期間 ${DAYS} 日）"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$TTEMP_KEY_WORK_DIR/key.pem" \
        -out "$TTEMP_KEY_WORK_DIR/cert.pem" \
        -days "$DAYS" \
        -subj "/CN=$IDENTITY" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE"

    P12_PASSWORD=$(uuidgen)
    printf '%s' "$P12_PASSWORD" > "$P12_PASSWORD_FILE"
    unset P12_PASSWORD
    chmod 600 "$P12_PASSWORD_FILE"
    openssl pkcs12 -export \
        -inkey "$TTEMP_KEY_WORK_DIR/key.pem" \
        -in "$TTEMP_KEY_WORK_DIR/cert.pem" \
        -name "$IDENTITY" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "file:$P12_PASSWORD_FILE" \
        -out "$P12"
    chmod 600 "$P12" "$P12_PASSWORD_FILE"

fi

# 既存P12も毎回互換形式へ再梱包する。古いSHA-256 MAC形式からの移行でも
# certificate/private keyはそのままなので、既存ユーザーのTCC同一性を壊さない。
repack_p12_for_apple_security

# signing/ を別マシンへ復元したケースでは、P12があってもidentityが未導入なので取り込む。
# 同名だが別証明書のidentityがある場合は曖昧な署名を避け、勝手に削除せず停止する。
EXPECTED_IDENTITY_SHA1=$(p12_certificate_sha1 "$P12")
INSTALLED_IDENTITY_SHA1=$(keychain_identity_sha1)
if [ -n "$INSTALLED_IDENTITY_SHA1" ] && [ "$INSTALLED_IDENTITY_SHA1" != "$EXPECTED_IDENTITY_SHA1" ]; then
    echo "ログインキーチェーンの '$IDENTITY' が $P12 と異なります。identityを整理してから再実行してください。" >&2
    exit 1
fi

if [ -z "$INSTALLED_IDENTITY_SHA1" ]; then
    echo "==> ログインキーチェーンへ取り込み"
    security import "$P12" -k "$KEYCHAIN" \
        -P "$(< "$P12_PASSWORD_FILE")" -T /usr/bin/codesign

    echo "==> 『コード署名で信頼』に設定（パスワードの確認が出ます）"
    openssl pkcs12 -in "$P12" -passin "file:$P12_PASSWORD_FILE" \
        -clcerts -nokeys -out "$TTEMP_KEY_WORK_DIR/cert.pem"
    security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TTEMP_KEY_WORK_DIR/cert.pem"
fi

INSTALLED_IDENTITY_SHA1=$(keychain_identity_sha1)
if [ "$INSTALLED_IDENTITY_SHA1" != "$EXPECTED_IDENTITY_SHA1" ]; then
    echo "identity が有効になっていません。キーチェーンアクセス.app で '$IDENTITY' を確認してください。" >&2
    exit 1
fi

# --- 2. Sparkle EdDSA 秘密鍵 ---

ED_KEY="$OUT_DIR/sparkle-ed-private-key"
if [ -s "$ED_KEY" ]; then
    echo "==> 既存の $ED_KEY を使う"
else
    if [ -e "$ED_KEY" ]; then
        echo "$ED_KEY が空か通常ファイルではありません。安全のため上書きしません。" >&2
        exit 1
    fi
    GENERATE_KEYS=$(find build/DerivedData/SourcePackages/artifacts -type f -name generate_keys -path '*/bin/*' 2>/dev/null | head -1)
    if [ -z "$GENERATE_KEYS" ]; then
        echo "Sparkle の generate_keys が見つかりません。SPM の解決が必要です:" >&2
        echo "  xcodegen generate && xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -derivedDataPath build/DerivedData -resolvePackageDependencies" >&2
        exit 1
    fi
    echo "==> Sparkle EdDSA 秘密鍵をキーチェーンからエクスポート"
    "$GENERATE_KEYS" -x "$ED_KEY"
    chmod 600 "$ED_KEY"
fi

# --- 3. GitHub シークレット登録 ---

echo "==> $REPO のリポジトリシークレットへ登録"
base64 -i "$P12" | tr -d '\r\n' | gh secret set SIGNING_CERT_P12 --repo "$REPO"
gh secret set SIGNING_CERT_PASSWORD --repo "$REPO" < "$P12_PASSWORD_FILE"
gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO" < "$ED_KEY"
gh secret list --repo "$REPO"

echo
echo "完了。main へ push すれば CI が全自動でリリースします。"
echo "signing/ の中身（.p12 / パスワード / EdDSA 鍵）は必ずどこか安全な場所にバックアップしてください。"
echo "別マシンでローカル署名したい場合は docs/SIGNING.md の「別マシンへの持ち出し」を参照。"
