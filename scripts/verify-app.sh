#!/bin/bash
# Static integrity is not enough: launch the exact signed executable, with a deadline.
set -euo pipefail
if [ "$#" -ne 1 ] || [ ! -x "$1/Contents/MacOS/Ttemp" ]; then
    echo "usage: $0 Ttemp.app" >&2
    exit 64
fi
APP=$(cd "$1" && pwd)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-verify.XXXXXX")
APP_PID=
WATCHDOG_PID=
cleanup() {
    [ -z "$WATCHDOG_PID" ] || kill "$WATCHDOG_PID" 2>/dev/null || true
    [ -z "$WATCHDOG_PID" ] || wait "$WATCHDOG_PID" 2>/dev/null || true
    [ -z "$APP_PID" ] || kill "$APP_PID" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/Ttemp" -verify_arch arm64 x86_64
test "$(/usr/libexec/PlistBuddy -c 'Print :LSRequiresNativeExecution' "$APP/Contents/Info.plist")" = true
certificate() {
    codesign -d -r- "$1" 2>&1 | sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p'
}
CERTIFICATE=$(certificate "$APP")
[[ "$CERTIFICATE" =~ ^[0-9a-f]{40}$ ]] || { echo "Expected stable certificate signature" >&2; exit 1; }
for component in "$APP" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"; do
    [ "$(certificate "$component")" = "$CERTIFICATE" ] || { echo "Mismatched helper identity: $component" >&2; exit 1; }
    for arch in arm64 x86_64; do
        codesign -d --verbose=4 --arch "$arch" "$component" 2>&1 | grep 'flags=.*runtime' >/dev/null
    done
done
codesign -d --entitlements - --xml "$APP" > "$WORK_DIR/entitlements.plist" 2>/dev/null
test "$(xmllint --xpath 'count(/plist/dict/key)' "$WORK_DIR/entitlements.plist")" = 1
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "$WORK_DIR/entitlements.plist")" = true

# Compile a valid non-platform library. dlopen must reject it specifically because
# of the distribution library constraint, not because it is missing or malformed.
printf '%s\n' 'int ttemp_probe(void) { return 42; }' > "$WORK_DIR/probe.c"
xcrun clang -dynamiclib "$WORK_DIR/probe.c" -o "$WORK_DIR/probe.dylib"
codesign --force --sign - "$WORK_DIR/probe.dylib"
"$APP/Contents/MacOS/Ttemp" --self-test --probe-library "$WORK_DIR/probe.dylib" > "$WORK_DIR/run.log" 2>&1 &
APP_PID=$!
(
    for ((i=0; i<45; i++)); do
        sleep 1
        kill -0 "$APP_PID" 2>/dev/null || exit 0
    done
    kill "$APP_PID" 2>/dev/null || true
) &
WATCHDOG_PID=$!
if wait "$APP_PID"; then
    APP_PID=
else
    APP_PID=
    cat "$WORK_DIR/run.log" >&2
    exit 1
fi
cat "$WORK_DIR/run.log"
grep -q '^TTEMP_SELF_TEST_OK ' "$WORK_DIR/run.log"
