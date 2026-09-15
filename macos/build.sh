#!/bin/bash
# Build Hingewave.app with the Swift toolchain alone (Xcode Command Line Tools suffice).
#
#   ./build.sh                 native Apple silicon build into build/Hingewave.app
#   ./build.sh --universal     Apple silicon plus Intel slices
#   ./build.sh --zip           also write build/Hingewave-mac.zip and build/SHA256SUMS.txt
#   ./build.sh --install       copy into /Applications (quits a running copy first)
#   ./build.sh --run           open the built or installed app
#
# HINGEWAVE_SIGNING_IDENTITY="Hingewave Release"  sign with a named identity instead of
# ad-hoc (HINGEWAVE_SIGNING_KEYCHAIN selects the keychain that holds it). Releases are
# signed with a self-signed "Hingewave Release" certificate so the Screen Recording
# grant survives updates; ad-hoc dev builds change identity on every build.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < ../VERSION)"
ARCHS=(arm64)
ZIP=0; INSTALL=0; RUN=0
for arg in "$@"; do
  case "$arg" in
    --universal) ARCHS=(arm64 x86_64) ;;
    --zip) ZIP=1 ;;
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ARCH_FLAGS=()
for a in "${ARCHS[@]}"; do ARCH_FLAGS+=(--arch "$a"); done

echo "building Hingewave $VERSION for ${ARCHS[*]}"
swift build -c release "${ARCH_FLAGS[@]}"
BIN=".build/apple/Products/Release/Hingewave"
[ -x "$BIN" ] || BIN=".build/release/Hingewave"

APP="build/Hingewave.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hingewave"
strip -x "$APP/Contents/MacOS/Hingewave" 2>/dev/null || true
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp Resources/Hingewave.icns "$APP/Contents/Resources/Hingewave.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${HINGEWAVE_SIGNING_IDENTITY:--}"
KEYCHAIN_ARGS=()
[ -n "${HINGEWAVE_SIGNING_KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$HINGEWAVE_SIGNING_KEYCHAIN")
codesign --force --deep --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP"

if [ "$ZIP" = 1 ]; then
  rm -f build/Hingewave-mac.zip
  ditto -c -k --keepParent "$APP" build/Hingewave-mac.zip
  (cd build && shasum -a 256 Hingewave-mac.zip > SHA256SUMS.txt)
  echo "wrote build/Hingewave-mac.zip and build/SHA256SUMS.txt"
fi

TARGET="$APP"
if [ "$INSTALL" = 1 ]; then
  pkill -x Hingewave 2>/dev/null || true
  rm -rf /Applications/Hingewave.app
  cp -R "$APP" /Applications/Hingewave.app
  TARGET=/Applications/Hingewave.app
  echo "installed $TARGET"
fi

if [ "$RUN" = 1 ]; then
  open "$TARGET"
fi
