#!/usr/bin/env bash
# Installs the latest Hingewave release into /Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Ant-lib/hingewave/main/macos/install.sh | bash
#
# What it does, in order: checks macOS 14 or later, downloads Hingewave-mac.zip and
# SHA256SUMS.txt from the latest GitHub release, verifies the checksum, unzips,
# replaces /Applications/Hingewave.app, clears the quarantine flag (the app is not
# notarized), and opens it. Nothing else is touched. Read it before running it.
#
# Set HINGEWAVE_LOCAL_ZIP=/path/to/Hingewave-mac.zip to install a local build instead.
set -euo pipefail

REPO="Ant-lib/hingewave"
APP="/Applications/Hingewave.app"
ASSET="Hingewave-mac.zip"
BUNDLE_ID="com.antlib.hingewave"

major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  echo "Hingewave needs macOS 14 Sonoma or later (this Mac runs $(sw_vers -productVersion))." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${HINGEWAVE_LOCAL_ZIP:-}" ]; then
  cp "$HINGEWAVE_LOCAL_ZIP" "$TMP/$ASSET"
  echo "using local $HINGEWAVE_LOCAL_ZIP"
else
  BASE="https://github.com/$REPO/releases/latest/download"
  echo "downloading $ASSET from the latest release"
  curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET"
  curl -fsSL -o "$TMP/SHA256SUMS.txt" "$BASE/SHA256SUMS.txt"
  (cd "$TMP" && grep " $ASSET\$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null) \
    || { echo "checksum mismatch for $ASSET; refusing to install" >&2; exit 1; }
  echo "checksum verified"
fi

ditto -x -k "$TMP/$ASSET" "$TMP/out"
[ -d "$TMP/out/Hingewave.app" ] || { echo "zip did not contain Hingewave.app" >&2; exit 1; }

pkill -x Hingewave 2>/dev/null || true
if [ -d "$APP" ]; then
  # Releases from 0.2.1 on are signed with one stable certificate, so the Screen
  # Recording grant survives updates. An older ad-hoc signed copy cannot keep its
  # grant; clear it so the new prompt attaches cleanly to this build.
  if codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$APP"
fi
ditto "$TMP/out/Hingewave.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"

cat <<'EOF'
Installed /Applications/Hingewave.app and opened it. A laptop icon is now in the menu bar.

One-time step: Hingewave asks for Screen Recording right now. Click Open System
Settings and turn on Hingewave under Privacy and Security, Screen Recording. Then
close the lid slowly. Hingewave only captures the built-in display while the lid is
moving and never stores or sends anything. The grant survives future updates.
EOF
