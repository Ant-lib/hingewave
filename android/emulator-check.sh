#!/usr/bin/env bash
# End-to-end check on a booted foldable emulator (the 7.6in Foldable profile).
#
# 1. Golden render check through the real GPU pipeline (render-check.sh).
# 2. Installs the debug APK, sets Hingewave as the live wallpaper through the
#    system chooser, drives the virtual hinge from 180 to 30 degrees and back,
#    and screenshots the home screen at each step into build/emulator-shots/.
#
# Needs: adb on PATH or ANDROID_HOME set, the emulator console reachable via
# `adb emu` (the token file is created by the emulator on first start).
set -euo pipefail
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"
OUT="build/emulator-shots"
mkdir -p "$OUT"

echo "== render check"
./render-check.sh

echo "== install"
./gradlew :app:assembleDebug -q --console=plain
"$ADB" install -r app/build/outputs/apk/debug/app-debug.apk >/dev/null

# Dumps the UI and taps the centre of the first clickable node whose text or
# description matches the regex. Prints 1 when tapped, 0 when nothing matched.
tap_label() {
  local pattern="$1"
  "$ADB" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || "$ADB" shell uiautomator dump /data/local/tmp/ui.xml >/dev/null
  "$ADB" pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1 || "$ADB" pull /data/local/tmp/ui.xml "$OUT/ui.xml" >/dev/null
  local bounds
  bounds="$(python3 - "$OUT/ui.xml" "$pattern" <<'PY'
import re, sys
xml = open(sys.argv[1], encoding="utf-8").read()
pattern = re.compile(sys.argv[2], re.I)
for m in re.finditer(r'<node[^>]*>', xml):
    node = m.group(0)
    text = re.search(r'text="([^"]*)"', node)
    desc = re.search(r'content-desc="([^"]*)"', node)
    label = ((text and text.group(1)) or "") + " " + ((desc and desc.group(1)) or "")
    if pattern.search(label) and 'clickable="true"' in node:
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
        if b:
            x1, y1, x2, y2 = map(int, b.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
PY
)"
  if [ -z "$bounds" ]; then echo 0; return; fi
  "$ADB" shell input tap $bounds
  echo 1
}

echo "== set live wallpaper"
"$ADB" shell am start -W -a android.service.wallpaper.CHANGE_LIVE_WALLPAPER \
  --ecn android.service.wallpaper.extra.LIVE_WALLPAPER_COMPONENT com.antlib.hingewave/.wallpaper.HingewaveWallpaperService >/dev/null
sleep 3
if [ "$(tap_label 'set wallpaper|apply')" != 1 ]; then
  echo "could not find the Set wallpaper button; UI dump saved to $OUT/ui.xml" >&2
  "$ADB" exec-out screencap -p > "$OUT/chooser.png"
  exit 1
fi
sleep 2
# Android 14 and later ask where to apply it.
tap_label 'home screen and lock screen|home and lock screen|home screen' >/dev/null
sleep 2
"$ADB" shell input keyevent KEYCODE_HOME
sleep 3
current="$("$ADB" shell dumpsys wallpaper | grep -m1 -o 'com.antlib.hingewave[^ ]*' || true)"
echo "wallpaper: ${current:-not set}"
if [ -z "$current" ]; then
  "$ADB" exec-out screencap -p > "$OUT/after-chooser.png"
  echo "live wallpaper was not applied; screenshot saved to $OUT/after-chooser.png" >&2
  exit 1
fi

echo "== hinge sweep"
for deg in 180 150 120 100 80 60 40 30 60 120 180; do
  "$ADB" emu sensor set hinge-angle0 "$deg" >/dev/null
  sleep 1.5
  "$ADB" exec-out screencap -p > "$OUT/inner-$(printf '%03d' "$deg").png"
  echo "  $deg deg -> $OUT/inner-$(printf '%03d' "$deg").png"
done
echo "done; screenshots in $OUT"
