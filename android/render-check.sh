#!/usr/bin/env bash
# Runs the golden render check on a connected device or emulator.
#
# Pushes core/test-card.png and core/golden to /data/local/tmp/hingewave-core,
# installs the debug app and its test APK, runs RenderCheckTest through the real
# GPU pipeline with `am instrument`, and pulls the rendered PNGs plus report.txt
# into android/build/render-check/. Gradle's connected test task is not used
# because it uninstalls the app afterwards, which would take the report with it.
set -euo pipefail
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"
PKG=com.antlib.hingewave

# /data/local/tmp exists on every device and emulator; /sdcard may not be mounted yet.
DEVICE_DIR=/data/local/tmp/hingewave-core
"$ADB" shell "rm -rf $DEVICE_DIR && mkdir -p $DEVICE_DIR/golden"
"$ADB" push ../core/test-card.png "$DEVICE_DIR/" >/dev/null
"$ADB" push ../core/golden/. "$DEVICE_DIR/golden/" >/dev/null
# The test runs as the app's uid, so the files must be world readable.
"$ADB" shell "chmod 755 $DEVICE_DIR $DEVICE_DIR/golden && chmod 644 $DEVICE_DIR/*.png $DEVICE_DIR/golden/*"

./gradlew :app:assembleDebug :app:assembleDebugAndroidTest -q --console=plain
"$ADB" install -r app/build/outputs/apk/debug/app-debug.apk >/dev/null
"$ADB" install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk >/dev/null

result="$("$ADB" shell am instrument -w -r -e class "$PKG.RenderCheckTest" "$PKG.test/androidx.test.runner.AndroidJUnitRunner" 2>&1 || true)"
echo "$result" | grep -E 'INSTRUMENTATION_STATUS: (test|stack)=|INSTRUMENTATION_RESULT|OK \(|FAILURES|Error' | head -20 || true

mkdir -p build/render-check
report="$("$ADB" shell run-as "$PKG" cat files/render-check/report.txt 2>/dev/null || true)"
if [ -n "$report" ]; then
  echo "$report" | tee build/render-check/report.txt
  for name in $(ls ../core/golden/*.png | xargs -n1 basename); do
    "$ADB" exec-out run-as "$PKG" cat "files/render-check/$name" > "build/render-check/$name" 2>/dev/null || true
  done
else
  echo "no render check report found on the device" >&2
fi

echo "$result" | grep -q 'OK (1 test)' && { echo "render check passed"; exit 0; }
echo "render check failed" >&2
exit 1
