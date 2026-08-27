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
# Use the platform tool that produced the distribution certificate; Homebrew's
# OpenSSL can add different default X.509 extensions to the same request.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Ttemp Release Test' \
    -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=critical,codeSigning' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -name 'Ttemp Release Test' \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:temporary-test-only -out "$WORK_DIR/cert.p12"
security create-keychain -p temporary-test-only "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p temporary-test-only "$KEYCHAIN"
security import "$WORK_DIR/cert.p12" -k "$KEYCHAIN" -P temporary-test-only -A -T /usr/bin/codesign
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
export TTEMP_KEYCHAIN="$KEYCHAIN"
TTEMP_SIGN_IDENTITY=$(/usr/bin/openssl x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 | sed 's/^.*=//;s/://g')
export TTEMP_SIGN_IDENTITY

# Match the production keychain setup and fail before building if the imported
# certificate/private-key pair is not usable on this macOS version.
[[ "$TTEMP_SIGN_IDENTITY" =~ ^[0-9A-F]{40}$ ]]
security find-certificate -a -Z "$KEYCHAIN" | grep -F "SHA-1 hash: $TTEMP_SIGN_IDENTITY"
security find-identity -p codesigning "$KEYCHAIN"
cp /usr/bin/true "$WORK_DIR/signing-probe"
codesign --force --sign "$TTEMP_SIGN_IDENTITY" --keychain "$KEYCHAIN" \
    --options runtime --timestamp=none "$WORK_DIR/signing-probe"
codesign --verify --strict --all-architectures "$WORK_DIR/signing-probe"
echo 'SIGNING_IDENTITY_TEST_OK'

xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
APP="build/DerivedData/Build/Products/Release/Ttemp.app"
./scripts/sign-app.sh "$APP"
./scripts/verify-app.sh "$APP"
ditto -c -k --keepParent "$APP" "$WORK_DIR/Ttemp.zip"
ditto -x -k "$WORK_DIR/Ttemp.zip" "$WORK_DIR/unpacked"
./scripts/verify-app.sh "$WORK_DIR/unpacked/Ttemp.app"

# Prove the runtime gate rejects a build that retains the launch exception but
# accidentally loses the replacement library constraint (codesign alone passes).
codesign --force --sign "$TTEMP_SIGN_IDENTITY" --keychain "$TTEMP_KEYCHAIN" \
    --options runtime --timestamp=none --entitlements Sources/App/Ttemp.entitlements \
    "$WORK_DIR/unpacked/Ttemp.app"
if ./scripts/verify-app.sh "$WORK_DIR/unpacked/Ttemp.app" > "$WORK_DIR/negative.log" 2>&1; then
    echo "Verifier accepted an unconstrained app" >&2
    exit 1
fi
grep -q 'Library constraint allowed unexpected third-party code' "$WORK_DIR/negative.log"
echo 'LIBRARY_CONSTRAINT_NEGATIVE_TEST_OK'
xcrun swift -module-cache-path "$WORK_DIR/swift-cache" scripts/verify-update.swift --self-test
./scripts/test-update.sh "$APP"
