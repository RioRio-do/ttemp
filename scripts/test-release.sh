#!/bin/bash
# PR-safe production-signing test. Disposable self-signed identity; no GitHub secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-release-test.XXXXXX")
KEYCHAIN="$WORK_DIR/test.keychain-db"
ORIGINAL_KEYCHAINS=()
while IFS= read -r path; do ORIGINAL_KEYCHAINS+=("$path"); done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//;s/"$//')
cleanup() {
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
umask 077
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Ttemp Release Test' \
    -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=critical,codeSigning' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:temporary-test-only -out "$WORK_DIR/cert.p12"
security create-keychain -p temporary-test-only "$KEYCHAIN"
security unlock-keychain -p temporary-test-only "$KEYCHAIN"
security import "$WORK_DIR/cert.p12" -k "$KEYCHAIN" -P temporary-test-only -A >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
export TTEMP_KEYCHAIN="$KEYCHAIN"
TTEMP_SIGN_IDENTITY=$(openssl x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 | sed 's/^.*=//;s/://g')
export TTEMP_SIGN_IDENTITY

xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
APP="build/DerivedData/Build/Products/Release/Ttemp.app"
./scripts/sign-app.sh "$APP"
./scripts/verify-app.sh "$APP"
ditto -c -k --keepParent "$APP" "$WORK_DIR/Ttemp.zip"
ditto -x -k "$WORK_DIR/Ttemp.zip" "$WORK_DIR/unpacked"
./scripts/verify-app.sh "$WORK_DIR/unpacked/Ttemp.app"
