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
# Let the launcher settle after the install; an "isn't responding" dialog would derail the chooser.
sleep 10
"$ADB" shell input keyevent KEYCODE_HOME
sleep 3

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
# Prefer a clickable match; fall back to any matching node, since list rows often
# carry the text on a child while the parent takes the click.
best = None
for m in re.finditer(r'<node[^>]*>', xml):
    node = m.group(0)
    text = re.search(r'text="([^"]*)"', node)
    desc = re.search(r'content-desc="([^"]*)"', node)
    label = ((text and text.group(1)) or "") + " " + ((desc and desc.group(1)) or "")
    if not pattern.search(label):
        continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
    if not b:
        continue
    clickable = 'clickable="true"' in node
    if best is None or (clickable and not best[0]):
        best = (clickable, b.groups())
    if clickable:
        break
if best:
    x1, y1, x2, y2 = map(int, best[1])
    print((x1 + x2) // 2, (y1 + y2) // 2)
PY
)"
  if [ -z "$bounds" ]; then echo 0; return; fi
  "$ADB" shell input tap $bounds
  echo 1
}

"$ADB" logcat -c 2>/dev/null || true
echo "== set live wallpaper"
# The emulator can be slow right after an install and show "isn't responding"
# dialogs; dismiss them with Wait and retry the chooser a few times.
opened=0
for attempt in 1 2 3 4; do
  "$ADB" shell am start -W -a android.service.wallpaper.CHANGE_LIVE_WALLPAPER \
    --ecn android.service.wallpaper.extra.LIVE_WALLPAPER_COMPONENT com.antlib.hingewave/.wallpaper.HingewaveWallpaperService >/dev/null
  sleep 4
  # The launcher can raise "isn't responding" on a slow runner; Wait keeps it alive.
  # Tap the button, never the title (the title is not clickable).
  if [ "$(tap_label '^Wait ?$')" = 1 ]; then
    echo "  pressed Wait on a not-responding dialog (attempt $attempt)"
    sleep 6
  elif [ "$(tap_label '^Close app ?$')" = 1 ]; then
    echo "  closed a not-responding app (attempt $attempt)"
    sleep 6
  fi
  if [ "$(tap_label 'set wallpaper|apply')" = 1 ]; then opened=1; break; fi
  echo "  chooser not ready (attempt $attempt)"
  sleep 3
done
if [ "$opened" != 1 ]; then
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
# The emulator animates the hinge to the requested angle over about two seconds,
# so each step waits before the screenshot. Files are indexed so the return sweep
# does not overwrite the closing sweep.
i=0
for deg in 180 150 120 100 80 60 40 30 60 120 180; do
  "$ADB" emu sensor set hinge-angle0 "$deg" >/dev/null
  sleep 3
  name="$OUT/$(printf '%02d' "$i")-inner-$(printf '%03d' "$deg").png"
  "$ADB" exec-out screencap -p > "$name"
  echo "  $deg deg -> $name"
  i=$((i + 1))
done
echo "== splash mode"
"$ADB" shell am broadcast -a com.antlib.hingewave.DEBUG_SETTINGS -n com.antlib.hingewave/.DebugSettingsReceiver --es effect splash | tail -1
sleep 2
echo "  prefs: $("$ADB" shell run-as com.antlib.hingewave cat shared_prefs/hingewave.xml 2>/dev/null | tr -d '\n' | grep -o '<string name="effectMode">[A-Z]*</string>')"
echo "  process: $("$ADB" shell pidof com.antlib.hingewave 2>/dev/null)"
# Switching modes plays one splash; let it drain (5 s still plus 1.5 s) before the sweep.
sleep 6
"$ADB" exec-out screencap -p > "$OUT/splash-00-before.png"
# A detent change triggers the ripple; the emulator animates the hinge so several
# sensor events arrive, which keeps the water alive until the five second stillness.
"$ADB" emu sensor set hinge-angle0 90 >/dev/null
i=0
for delay in 0.3 0.5 0.6 1.0 3.0; do
  sleep "$delay"
  i=$((i + 1))
  "$ADB" exec-out screencap -p > "$OUT/splash-$(printf '%02d' "$i").png"
  echo "  splash frame $i -> $OUT/splash-$(printf '%02d' "$i").png"
done
sleep 5
"$ADB" exec-out screencap -p > "$OUT/splash-drained.png"
echo "  drained -> $OUT/splash-drained.png"
"$ADB" shell am broadcast -a com.antlib.hingewave.DEBUG_SETTINGS -n com.antlib.hingewave/.DebugSettingsReceiver --es effect auto >/dev/null
"$ADB" emu sensor set hinge-angle0 180 >/dev/null

"$ADB" logcat -d -s Hingewave:* AndroidRuntime:E 2>/dev/null | tail -60 > "$OUT/logcat.txt" || true
echo "done; screenshots in $OUT"
