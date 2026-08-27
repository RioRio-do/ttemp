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
    [ -z "$APP_PID" ] || kill "$APP_PID" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/Ttemp" -verify_arch arm64 x86_64

# Compile a valid non-platform library. dlopen must reject it specifically because
# of the distribution library constraint, not because it is missing or malformed.
printf '%s\n' 'int ttemp_probe(void) { return 42; }' > "$WORK_DIR/probe.c"
xcrun clang -dynamiclib "$WORK_DIR/probe.c" -o "$WORK_DIR/probe.dylib"
codesign --force --sign - "$WORK_DIR/probe.dylib"
"$APP/Contents/MacOS/Ttemp" --self-test --probe-library "$WORK_DIR/probe.dylib" > "$WORK_DIR/run.log" 2>&1 &
APP_PID=$!
(
    sleep 45
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
