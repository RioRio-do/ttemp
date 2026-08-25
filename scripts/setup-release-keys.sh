#!/bin/bash
# リリースに使う鍵一式を用意し、GitHub Actions のリポジトリシークレットへ登録する。
#
# やること:
#   1. コード署名証明書「Ttemp Signing」を作り直し、.p12 を signing/ に保存して
#      ログインキーチェーンにも取り込む（既存 identity は p12 が残っていないため削除する）
#   2. Sparkle EdDSA 秘密鍵をキーチェーンから signing/ にエクスポート
#   3. 3つのシークレットを gh で登録:
#        SIGNING_CERT_P12       … .p12 の base64
#        SIGNING_CERT_PASSWORD  … .p12 のパスワード
#        SPARKLE_ED_PRIVATE_KEY … Sparkle EdDSA 秘密鍵
#
# 実行は原則一度だけ。証明書を作り直すと、配布済みアプリの TCC 許可（入力監視）と
# 自分のマシンの許可が一度リセットされる。signing/ の中身は git 管理外なので、
# パスワードマネージャ等に必ずバックアップすること。
#
# 途中でキーチェーンの確認ダイアログ（信頼設定・鍵アクセス）が出たら許可すること。

set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Ttemp Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OUT_DIR="signing"
REPO="RioRio-do/ttemp"
DAYS=3650

command -v gh >/dev/null || { echo "gh (GitHub CLI) が必要です: brew install gh" >&2; exit 1; }
gh auth status >/dev/null || { echo "gh auth login でログインしてください" >&2; exit 1; }

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# --- 1. コード署名証明書 ---

P12="$OUT_DIR/ttemp-signing.p12"
P12_PASSWORD_FILE="$OUT_DIR/ttemp-signing.p12.password"

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
    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$WORKDIR/key.pem" \
        -out "$WORKDIR/cert.pem" \
        -days "$DAYS" \
        -subj "/CN=$IDENTITY" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE"

    P12_PASSWORD=$(uuidgen)
    # 暗号方式を AES に固定する（既定の RC2/3DES は CI ランナーの openssl が
    # 読めないことがある。macOS の security import は AES を読める）
    openssl pkcs12 -export \
        -inkey "$WORKDIR/key.pem" \
        -in "$WORKDIR/cert.pem" \
        -name "$IDENTITY" \
        -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256 \
        -passout "pass:$P12_PASSWORD" \
        -out "$P12"
    printf '%s' "$P12_PASSWORD" > "$P12_PASSWORD_FILE"
    chmod 600 "$P12" "$P12_PASSWORD_FILE"

    echo "==> ログインキーチェーンへ取り込み"
    security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

    echo "==> 『コード署名で信頼』に設定（パスワードの確認が出ます）"
    security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

    security find-identity -v -p codesigning | grep -q "$IDENTITY" || {
        echo "identity が有効になっていません。キーチェーンアクセス.app で '$IDENTITY' を確認してください。" >&2
        exit 1
    }
fi

# --- 2. Sparkle EdDSA 秘密鍵 ---

ED_KEY="$OUT_DIR/sparkle-ed-private-key"
if [ -f "$ED_KEY" ]; then
    echo "==> 既存の $ED_KEY を使う"
else
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
base64 -i "$P12" | gh secret set SIGNING_CERT_P12 --repo "$REPO"
gh secret set SIGNING_CERT_PASSWORD --repo "$REPO" < "$P12_PASSWORD_FILE"
gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO" < "$ED_KEY"
gh secret list --repo "$REPO"

echo
echo "完了。main へ push すれば CI が全自動でリリースします。"
echo "signing/ の中身（.p12 / パスワード / EdDSA 鍵）は必ずどこか安全な場所にバックアップしてください。"
echo "別マシンでローカル署名したい場合は docs/SIGNING.md の「別マシンへの持ち出し」を参照。"
