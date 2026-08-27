#!/bin/bash
# Exercise Sparkle's real helpers against disposable app copies and a loopback feed.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TTEMP_SIGN_IDENTITY:?Run through scripts/test-release.sh with a disposable signing identity}"
: "${TTEMP_KEYCHAIN:?Run through scripts/test-release.sh with a disposable keychain}"
APP=$(cd "${1:-build/DerivedData/Build/Products/Release/Ttemp.app}" && pwd)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ttemp-update-test.XXXXXX")
SERVER_PID=
WATCHDOG_PID=
CLI_PID=
fixture() { xcrun swift -module-cache-path "$WORK_DIR/swift-cache" scripts/update-fixture.swift "$@"; }
cleanup() {
    [ -z "$CLI_PID" ] || kill "$CLI_PID" 2>/dev/null || true
    [ -z "$WATCHDOG_PID" ] || kill "$WATCHDOG_PID" 2>/dev/null || true
    [ -z "$SERVER_PID" ] || kill "$SERVER_PID" 2>/dev/null || true
    [ -z "$SERVER_PID" ] || wait "$SERVER_PID" 2>/dev/null || true
    for scenario in bad-feed bad-archive valid; do
        fixture cleanup "$WORK_DIR/$scenario" || true
    done
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
umask 077
mkdir "$WORK_DIR/served"
# Only this temporary directory is served, and only to this Mac.
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$WORK_DIR/served" > "$WORK_DIR/server.log" 2>&1 &
SERVER_PID=$!
for ((i=0; i<50; i++)); do
    PORT=$(sed -n 's/.*port \([0-9]*\) .*/\1/p' "$WORK_DIR/server.log")
    [ -z "$PORT" ] || break
    sleep 0.1
done
[[ "$PORT" =~ ^[0-9]+$ ]] || { cat "$WORK_DIR/server.log" >&2; exit 1; }
URL="http://127.0.0.1:$PORT"

# Compile the CLI from the same pinned Sparkle revision as the app; not a separate
# downloaded tool. Load the exact signed framework embedded by our release build.
SPARKLE_SOURCE=build/DerivedData/SourcePackages/checkouts/Sparkle/sparkle-cli
SPARKLE_FRAMEWORKS=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64
xcrun clang -fobjc-arc -fmodules -F "$SPARKLE_FRAMEWORKS" \
    '-DSPU_OBJC_DIRECT=__attribute__((objc_direct))' \
    '-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))' \
    -framework AppKit -framework Sparkle -Wl,-rpath,"$APP/Contents/Frameworks" \
    "$SPARKLE_SOURCE/main.m" "$SPARKLE_SOURCE/SPUCommandLineDriver.m" \
    "$SPARKLE_SOURCE/SPUCommandLineUserDriver.m" -o "$WORK_DIR/sparkle-cli"
run_update() {
    "$WORK_DIR/sparkle-cli" "$1/old/Ttemp.app" --check-immediately \
        --feed-url "$2" --user-agent-name Ttemp-Local-Test --verbose > "$WORK_DIR/update.log" 2>&1 &
    CLI_PID=$!
    (
        for ((i=0; i<45; i++)); do
            sleep 1
            kill -0 "$CLI_PID" 2>/dev/null || exit 0
        done
        kill "$CLI_PID" 2>/dev/null || true
    ) &
    WATCHDOG_PID=$!
    local result=0
    wait "$CLI_PID" || result=$?
    CLI_PID=
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    WATCHDOG_PID=
    cat "$WORK_DIR/update.log"
    return "$result"
}
# The CLI exits as soon as a cycle ends; failed installers may still be cleaning
# up asynchronously. Use independent bundle IDs/paths for independent scenarios.
for scenario in bad-feed bad-archive valid; do
    CASE_DIR="$WORK_DIR/$scenario"
    mkdir "$CASE_DIR" "$WORK_DIR/served/$scenario"
    ln -s "$WORK_DIR/served/$scenario" "$CASE_DIR/feed"
    fixture prepare "$CASE_DIR" "$APP" "$URL/$scenario"
    ./scripts/sign-app.sh "$CASE_DIR/old/Ttemp.app"
    ./scripts/sign-app.sh "$CASE_DIR/new/Ttemp.app"
    ditto -c -k --keepParent "$CASE_DIR/new/Ttemp.app" "$CASE_DIR/feed/Ttemp.zip"
    fixture sign "$CASE_DIR"
    if [ "$scenario" = valid ]; then
        run_update "$CASE_DIR" "$URL/$scenario/appcast.xml"
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CASE_DIR/old/Ttemp.app/Contents/Info.plist")" = 2
        ./scripts/verify-app.sh "$CASE_DIR/old/Ttemp.app"
    else
        FEED=appcast.xml
        if [ "$scenario" = bad-feed ]; then
            FEED=bad-appcast.xml
        else
            fixture tamper-archive "$CASE_DIR"
        fi
        if run_update "$CASE_DIR" "$URL/$scenario/$FEED"; then
            echo "Sparkle accepted $scenario" >&2
            exit 1
        fi
        grep -q 'improperly signed' "$WORK_DIR/update.log"
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CASE_DIR/old/Ttemp.app/Contents/Info.plist")" = 1
    fi
done
echo 'SPARKLE_UPDATE_E2E_OK (invalid feed/archive rejected, helpers installed update, updated app launched)'
