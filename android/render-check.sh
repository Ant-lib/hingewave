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

./gradlew :app:connectedDebugAndroidTest --console=plain \
  -Pandroid.testInstrumentationRunnerArguments.class=com.antlib.hingewave.RenderCheckTest 2>&1 \
  | grep -E 'RenderCheckTest|Tests? |BUILD|FAIL|error|Exception' || true
status=${PIPESTATUS[0]}

mkdir -p build/render-check
report="$("$ADB" shell run-as com.antlib.hingewave cat files/render-check/report.txt 2>/dev/null || true)"
if [ -n "$report" ]; then
  echo "$report" | tee build/render-check/report.txt
  for name in $(ls ../core/golden/*.png | xargs -n1 basename); do
    "$ADB" exec-out run-as com.antlib.hingewave cat "files/render-check/$name" > "build/render-check/$name" 2>/dev/null || true
  done
else
  echo "no render check report found on the device" >&2
fi
exit "${status:-0}"
