#!/bin/bash
# Sign nested Sparkle code inside-out. Never use --deep for signing.
set -euo pipefail
if [ "$#" -ne 1 ] || [ ! -d "$1/Contents/Frameworks/Sparkle.framework" ]; then
    echo "usage: $0 Ttemp.app" >&2
    exit 64
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$1" && pwd)
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
IDENTITY=${TTEMP_SIGN_IDENTITY:-Ttemp Signing}
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-sign.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --timestamp=none)
[ -z "${TTEMP_KEYCHAIN:-}" ] || SIGN_ARGS+=(--keychain "$TTEMP_KEYCHAIN")

# Code Sign on Copy does not sign the nested helpers. Preserve Downloader's
# vendor entitlements, but never give helpers the app's library-validation exception.
for component in XPCServices/Installer.xpc Autoupdate Updater.app; do
    codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/$component"
done
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"

# macOS 14+ library constraints allow exact third-party code without an Apple
# Team ID. OS libraries are exempt by the OS; no arbitrary third-party ID is allowed.
CONSTRAINT="$WORK_DIR/libraries.plist"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict><key>cdhash</key><dict><key>$in</key><array>'
    for arch in $(lipo -archs "$FRAMEWORK/Versions/B/Sparkle"); do
        hash=$(codesign -d --verbose=4 --arch "$arch" "$FRAMEWORK" 2>&1 | sed -n 's/^CDHash=//p')
        [[ "$hash" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid Sparkle CDHash" >&2; exit 1; }
        printf '<data>'
        printf '%s' "$hash" | xxd -r -p | base64
        printf '%s\n' '</data>'
    done
    printf '%s\n' '</array></dict></dict></plist>'
} > "$CONSTRAINT"
codesign --validate-constraint "$CONSTRAINT"
codesign "${SIGN_ARGS[@]}" --entitlements "$SCRIPT_DIR/../Sources/App/Ttemp.entitlements" \
    --library-constraint "$CONSTRAINT" --enforce-constraint-validity "$APP"
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
