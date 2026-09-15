# Hingewave

**The iPhone Duo fold animation for your MacBook lid, Windows laptop and Android foldable.**

Close the lid and the desktop stays anchored in space while the glass tilts over it, blurring and darkening from the hinge outward. Open it and the picture comes back. The physical hinge is the timeline: Hingewave reads the angle sensor every 20 ms and redraws on the GPU, so the motion of your hand is the motion on screen.

![The effect at four lid angles](docs/assets/fold-frames.png)

One repository, three native apps, one shared definition of the effect. macOS ships first. Android and Windows follow on the same core.

## Install

### macOS

```sh
curl -fsSL https://raw.githubusercontent.com/Ant-lib/hingewave/main/macos/install.sh | bash
```

That downloads the latest release, verifies its checksum, puts Hingewave in Applications and opens it. A laptop icon appears in the menu bar. macOS then asks for Screen Recording once: turn on Hingewave under System Settings, Privacy and Security, Screen Recording. Now close the lid slowly.

Homebrew users can run `brew install --cask --no-quarantine ant-lib/tap/hingewave` once the tap is published.

Prefer a manual install? Download `Hingewave-mac.zip` from [Releases](https://github.com/Ant-lib/hingewave/releases), unzip, and drag Hingewave.app into Applications. The app is not notarized, so on first open go to System Settings, Privacy and Security, and click Open Anyway.

Requirements: macOS 14 Sonoma or later and a MacBook with a lid angle sensor. That is the 2019 16-inch MacBook Pro and later, MacBook Air with M2 or later, and 14-inch or 16-inch MacBook Pro with M1 Pro or later. The M1 MacBook Air and the 13-inch M1 and M2 MacBook Pro have no continuous sensor; the menu says so and the app stays idle.

### Android and Windows

Coming. The design and the shared core are ready; see [docs/design.md](docs/design.md) for the plan, including which foldables expose a usable hinge angle (Galaxy Z Fold 8 and Pixel Folds yes, Galaxy Z Fold 7 and earlier no) and how Windows laptops without a hinge sensor are handled.

## Using it

The menu has four items. **Follow the Lid** turns the effect off and on. **Preview Fold** plays a scripted close and reopen so you can see the effect without touching the lid; before Screen Recording is granted it folds a generated picture instead of your desktop. **Launch at Login** does what it says. **Quit** quits.

Good to know:

- A nudge while typing does not trigger it. The lid has to be closing at a deliberate pace when it crosses 90 degrees.
- Stop part way and the desktop clears back after two seconds, so you can work at any angle.
- Reopen before the Mac sleeps and the effect plays in reverse. Once it has slept, waking ends the effect immediately.
- With an external monitor attached, the effect ends when the built-in display switches off. Nothing lands on the monitor.
- Reduce Motion in System Settings disables the tilt; blur and darkening still follow the lid.

## How it works

| Piece | Role |
|---|---|
| `core/effect.json` | The tuned numbers: eye distance, blur, darkening, spring, angles. One file for every platform. |
| `core/reference/` | Python reference implementation of the motion model and the shader math. Generates the fixtures and golden images every port must pass. |
| `macos/Sources/Hingewave/LidAngleSensor.swift` | Reads the hinge angle over IOKit HID (usage page 0x20, usage 0x8A). Hundredths of a degree on Apple silicon. No permission needed. |
| `macos/Sources/HingewaveCore/LaptopMotionModel.swift` | Critically damped spring plus the idle, armed, active, clearing state machine. Verified against `core/fixtures`. |
| `macos/Sources/Hingewave/ScreenStreamer.swift` | Streams the built-in display through ScreenCaptureKit into Metal textures. Runs only while the lid moves. |
| `macos/Sources/Hingewave/FoldShader.swift` | One Metal fragment pass: perspective hold onto the resting plane, mip-chain blur growing from the hinge, darkening. Verified against `core/golden` by PSNR. |
| `macos/Sources/Hingewave/OverlayWindow.swift` | Click-through window over the built-in display, excluded from every screen capture so it never feeds back into its own picture. |

The full design, including the math, is in [docs/design.md](docs/design.md).

## Privacy

No network access, no analytics, no accounts. Screen frames go from ScreenCaptureKit to Metal and never leave the GPU; they are dropped when the effect clears. Screens the system marks secure are not captured. Events are appended to `~/Library/Logs/Hingewave.log`; that log never contains screen content.

## Build from source

The Xcode Command Line Tools are enough (`xcode-select --install`). The Metal shader compiles at runtime, so full Xcode is not required.

```sh
git clone https://github.com/Ant-lib/hingewave.git
cd hingewave/macos
./build.sh --install --run
```

`./build.sh --universal --zip` produces the release zip with an Intel slice. `swift test` runs the motion model against the shared fixtures. Debug flags on the built binary:

```
Hingewave --probe 5              print the lid angle for five seconds
Hingewave --render-check /tmp/rc render the golden set through Metal and report PSNR
Hingewave --simulate-close       scripted 120 to 0 to 120 sweep over the live desktop
Hingewave --demo                 the same sweep over a generated picture, no permission needed
Hingewave --preview 45           move to one angle and hold until the effect clears
```

The reference implementation needs Python 3 with NumPy and Pillow: `pip install -e "core/reference[test]"`, then `python -m pytest core/reference` and, after changing the effect, `python -m hingewave_ref regen` from `core/reference`.

## Verified hardware

| Platform | Device | Status |
|---|---|---|
| macOS | 14-inch MacBook Pro, M1 Pro, macOS 26 | Sensor, motion model, renderer and demo overlay verified. Live capture pending a Screen Recording grant on the test machine. |
| Android | Galaxy Z Fold 8 | Not started |
| Windows | Lenovo Yoga 7i 2-in-1 | Not started |

Reports from other machines are welcome as issues: include the Mac model, macOS version, and what `Hingewave --probe` prints.

## Credits

The lid angle sensor was documented by [Sam Henri Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) (Apache 2.0). [Lidfold](https://github.com/colehollander10-netizen/lidfold) and [Mac Duo](https://github.com/DhananjayBhosale/MacDuo) showed the way on macOS; [duo-open](https://github.com/marcoazeem/duo-open) and [FoldFX](https://github.com/iamkeeler/FoldFX) on Android. Hingewave is independent work and is not affiliated with Apple, Samsung, Google or Microsoft. iPhone, iPhone Duo and MacBook are trademarks of Apple Inc.

## License

MIT. See [LICENSE](LICENSE).
