#!/usr/bin/env bash
# Runs the golden render check on a connected device or emulator.
#
# Pushes core/test-card.png and core/golden to /sdcard/hingewave-core, runs the
# instrumented RenderCheckTest through the real GPU pipeline, and pulls the
# rendered PNGs plus report.txt into android/build/render-check/.
set -euo pipefail
cd "$(dirname "$0")"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"

# /data/local/tmp exists on every device and emulator; /sdcard may not be mounted yet.
DEVICE_DIR=/data/local/tmp/hingewave-core
"$ADB" shell "rm -rf $DEVICE_DIR && mkdir -p $DEVICE_DIR/golden"
"$ADB" push ../core/test-card.png "$DEVICE_DIR/" >/dev/null
"$ADB" push ../core/golden/. "$DEVICE_DIR/golden/" >/dev/null
# The test runs as the app's uid, so the files must be world readable.
"$ADB" shell "chmod 755 $DEVICE_DIR $DEVICE_DIR/golden && chmod 644 $DEVICE_DIR/*.png $DEVICE_DIR/golden/*"

./gradlew :app:connectedDebugAndroidTest -q --console=plain \
  -Pandroid.testInstrumentationRunnerArguments.class=com.antlib.hingewave.RenderCheckTest || status=$?

mkdir -p build/render-check
"$ADB" shell "run-as com.antlib.hingewave sh -c 'cd files/render-check && tar cf - .'" 2>/dev/null | tar xf - -C build/render-check || true
[ -f build/render-check/report.txt ] && cat build/render-check/report.txt
exit "${status:-0}"
