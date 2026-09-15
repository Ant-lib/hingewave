Hingewave 0.2.0. Downloads for all three platforms, universal Mac binary, ad-hoc signed, not notarized.

New in this release:

- The macOS and Windows fold starts from wherever your lid rests (105 degrees or 130), once the lid has closed 5 degrees at a deliberate pace, instead of a fixed 90 degree gate.
- Splash mode for foldables that only report 0, 90 and 180 degrees (Galaxy Z Fold 7 and earlier, Z Flip 5 and 6): a ripple leaves the hinge when the phone starts opening or closing, keeps breathing while you handle it, and drains after five seconds without movement. Picked automatically on those devices, or by hand in the settings screen.
- One icon on every platform.
- macOS retries lid sensor detection and pauses cleanly if the sensor stops answering.

Install on macOS with one line:

```
curl -fsSL https://raw.githubusercontent.com/Ant-lib/hingewave/main/macos/install.sh | bash
```

Or with Homebrew: `brew trust ant-lib/tap`, `brew tap ant-lib/tap`, `brew install --cask ant-lib/tap/hingewave`. Verify downloads against the SHA256SUMS files. See the README for Android and Windows.
