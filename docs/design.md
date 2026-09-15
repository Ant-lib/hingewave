# Hingewave design

Status: approved design, September 2026.

Hingewave brings the iPhone Duo fold animation to laptop lids and Android foldables.
As the hinge moves, the on-screen picture stays anchored in space while the panel
tilts around it, blurs from the hinge outward and darkens. The physical hinge is the
timeline: nothing is a canned animation.

One repository, three native apps, one shared definition of the effect.

## 1. Goals and non-goals

Goals:

- The same effect, defined once in `core/`, on macOS, Android and Windows.
- One-command install on every platform.
- No network, no telemetry, no accounts. Screen content never leaves the GPU.
- Honest capability detection. When a device cannot deliver the real thing, the app
  says so and falls back to something simpler rather than pretending.

Non-goals:

- Replacing the operating system's own display handover on foldables. Only the OEM
  can do that.
- App Store or Microsoft Store distribution. macOS needs an undocumented sensor and
  screen capture; neither is store-safe.
- Multiple effect styles. Hingewave ships exactly one effect and tunes it well.

## 2. The effect

Inputs per frame: the current hinge angle and the last captured picture of the panel.

Three operations, applied in one fragment shader:

1. Perspective hold. The picture is treated as sitting on the plane the panel rested
   on. As the panel tilts, each display pixel is traced from an assumed eye position
   to that resting plane, so the picture keystones: pinned at the hinge, narrowing
   away from it. The picture appears to stay still while the glass moves over it.
2. Progressive blur. Blur radius grows linearly with distance from the hinge and
   with fold progress. Zero at the hinge, maximum at the far edge.
3. Darkening. A gradient from the hinge outward, driven by progress at twice the
   strength of the blur, so the panel reads as going dark before it is fully closed.

Opening plays the same mapping in reverse. Stopping part way lets the picture settle
back to normal after a short stillness timeout.

### 2.1 Coordinates

Normalised panel space. `u` runs perpendicular to the hinge, 0 at the hinge and 1 at
the far edge. `v` runs along the hinge, 0 to 1. `A` is the aspect ratio, length along
the hinge divided by length perpendicular to it. Every platform maps its own pixel
grid and hinge edge (bottom for laptops, left or right for phones) into this space
before the shared math runs, and maps the result back afterwards.

### 2.2 Perspective hold

Physical units are panel heights. The resting plane is `z = 0`; a picture point is
`(x, y, 0)` with `x = (v - 0.5) * A` and `y = u`. The panel tilts by `tau` radians
about the hinge line (`y = 0, z = 0`), positive toward the viewer. The display point
for pixel `(u, v)` is:

```
D = ((v - 0.5) * A,  u * cos(tau),  u * sin(tau))
```

The eye sits at `E = (0, 0.5, d)`, `d` panel heights in front of the resting plane,
level with the panel centre. The ray from `E` through `D` meets the resting plane at
parameter `t = d / (d - D.z)`, giving picture coordinates:

```
u' = 0.5 + t * (u * cos(tau) - 0.5)
v' = 0.5 + t * (v - 0.5)
```

Pixels whose `(u', v')` fall outside `[0, 1]` are black. There is no head tracking;
`d` is a tuned guess and is the strength knob of the illusion.

### 2.3 Blur

Radius in pixels at display pixel `(u, v)`:

```
r = maxBlur * H * progress * u
```

where `H` is the panel extent perpendicular to the hinge in pixels and `maxBlur` is a
fraction of that extent. The reference kernel is Gaussian with standard deviation
`r / 2`, truncated at two standard deviations. Ports may implement it with a mip
chain or blur pyramid sampled at `log2(r)`; the golden-image tolerance in section 4
allows for kernel differences.

### 2.4 Darkening

```
k = clamp(darkenGain * progress * (0.35 + 0.65 * u), 0, 1)
colour = colour * (1 - k)
```

### 2.5 Tuned defaults

Stored once in `core/effect.json` and loaded by every port. Reconstructed from public
footage of the iPhone Duo and from the best existing recreations, so treat them as a
starting point, not scripture.

| Key | Default | Meaning |
|---|---|---|
| `eyeDistance` | 2.0 | Eye distance in panel heights |
| `maxBlur` | 0.036 | Blur radius at the far edge as a fraction of panel height (72 px on a 1964 px panel) |
| `darkenGain` | 2.0 | Darkening strength relative to progress |
| `springHz` | 6.0 | Natural frequency of the angle smoother |
| `stillSeconds` | 2.0 | Stillness before the picture clears back |
| `clearSeconds` | 0.6 | Duration of the clear-back animation |
| `laptop.armDelta` | 5 | Degrees the lid must close from its resting angle before the effect arms |
| `laptop.restSeconds` | 0.3 | Stillness needed while idle before the current angle becomes the resting angle |
| `laptop.endAngle` | 8 | Lid angle where the panel is fully dark |
| `laptop.armVelocity` | 15 | Closing speed in degrees per second required when the arming distance is reached |
| `phone.deadZone` | 6 | Degrees from 0 and 180 treated as settled |
| `phone.inner.clearStart` | 100 | Inner panel is fully frosted at or below this angle |
| `phone.inner.clearEnd` | 174 | Inner panel is fully clear at or above this angle |
| `phone.cover.frostStart` | 6 | Cover panel starts frosting on open |
| `phone.cover.frostEnd` | 26 | Cover panel is fully frosted |
| `splash.travelSeconds` | 1.2 | Ripple front travel time from hinge to far edge |
| `splash.riseSeconds` | 0.25 | Water rise time at a trigger |
| `splash.stillSeconds` | 5.0 | Stillness before the water drains |
| `splash.drainSeconds` | 1.5 | Drain duration |
| `splash.swellHz` | 0.4 | Standing swell frequency while holding |
| `splash.motionThreshold` | 0.3 | Gyroscope magnitude in rad/s that counts as movement |

## 3. Motion model

The motion model turns raw sensor samples into `(state, tilt, progress)` per frame. It
is specified here and implemented as a small pure module in each port, verified by
shared fixtures rather than shared code. Sharing 150 lines through FFI would cost
every contributor a second toolchain.

### 3.1 Smoothing

A critically damped spring with natural frequency `springHz` follows the raw angle.
It hides one-degree sensor steps without visible lag. The spring is integrated with
the exact closed-form step so the result does not depend on frame rate. Velocity is
read from the spring state.

### 3.2 Laptop state machine

States: `idle`, `armed`, `active`, `clearing`.

- `idle`: nothing rendered, capture stopped, sensor polled. The model keeps a
  resting angle: whenever the smoothed angle has been still (speed under 2 degrees
  per second) for `restSeconds`, the current angle becomes the rest. The first
  sample seeds it. So the effect starts from wherever the lid was, 105 degrees or
  130, not from a fixed threshold.
- `idle -> armed`: the smoothed angle is at least `armDelta` below the resting angle
  and the closing speed is at or above `armVelocity`. Capture starts warming up. A
  nudge while typing does not arm because it is too slow.
- `armed -> active`: the first captured frame is ready. The overlay appears.
- In `active`: `tilt = max(0, rest - angle)` in degrees, converted to radians for the
  shader. `progress = smoothstep((rest - angle) / (rest - endAngle))`, clamped to
  `[0, 1]`. Reopening lowers both; the effect plays in reverse.
- `active -> clearing`: the angle has been still (speed under 2 degrees per second)
  for `stillSeconds` and is above `endAngle + 2`, or the angle rises back to within
  2 degrees of the resting angle. A multiplier animates from 1 to 0 over
  `clearSeconds` and scales both tilt and progress.
- `clearing -> idle`: the multiplier reaches 0. Capture stops. The resting angle is
  re-anchored at the current angle, so a lid left half closed can be closed further
  and the effect starts again from there.
- Any state `-> idle` immediately when the built-in display turns off, the sensor
  fails, or capture fails. The desktop is never left tilted.
- Reduce Motion: tilt is disabled; blur and darkening still follow the angle.

### 3.3 Phone mapping

Live wallpapers are stateless with respect to arming: each sensor event maps
straight through the spring to progress. `tilt = 180 - angle` on the moving half.
Inner panel: `progress = 1 - smoothstep((angle - clearStart) / (clearEnd -
clearStart))`. Cover panel: `progress = smoothstep((angle - frostStart) / (frostEnd
- frostStart))`. Angles within `deadZone` of 0 or 180 count as settled.

Detent detection: if the first twelve sensor events all carry values in `{0, 90,
180}`, the sensor is detent-only; any other value decides continuous at once. The wallpaper then plays a fixed `clearSeconds`
transition on each change and reports "detent-only sensor" in its settings screen.

Span calibration: a live wallpaper only receives events while its panel is lit, and
the inner panel lights part way through an unfold. The engine records the span of
angles it actually observes; the settings screen offers that span as the effective
`clearStart` with one button.

### 3.3a Splash mode for detent-only foldables

Galaxy Z Fold 7 and earlier, Z Flip 5 and 6 and the Z TriFold report only 0, 90
and 180 to apps, so the fold cannot follow the hinge there. Splash mode replaces it:

- Triggers: a different panel lighting up (the inner panel part way through an
  opening, the cover when closing), or any change in the detent value. Reaching 0 or
  180 is a settle.
- Motion: the gyroscope above `splash.motionThreshold` rad/s counts as "still being
  handled" and postpones the drain.
- Timeline (`SplashTimeline`, fixtures `splash-*.json`): `idle -> splashing` on a
  trigger; water rises over `riseSeconds`; the ripple front travels from the hinge to
  the far edge in `travelSeconds`; then `holding` with a slow swell at `swellHz`. After
  `stillSeconds` without trigger or motion, or after a settle once the front has
  passed the far edge, `draining` scales the water to zero over `drainSeconds` and
  the wallpaper is sharp again. A trigger while draining restarts the ripple from
  the current water level so nothing pops.
- Shader: a derivative-of-Gaussian refraction ring with a bright crest, a standing
  swell behind it, a wet tint, and five droplets trailing the front. The inner panel
  ripples from the centre crease both ways; the cover from its inner edge.
- Selection: `effectMode` Auto (Splash when the detector says detent-only or no
  sensor), Fold, or Splash. There is no golden image for the ripple; the timeline is
  fixture-verified and the emulator sweep captures frames.

### 3.4 Windows tiers

The angle source is chosen at startup, best available first:

1. `HingeAngleSensor` (WinRT). Continuous degrees. Rare on laptops but supported.
2. Lid accelerometer. Convertibles expose the lid's accelerometer for auto-rotate.
   With the base assumed level, lid angle is `atan2(-a.y, a.z)` in the sensor's fixed
   coordinate frame. A two-position calibration on first run (lid at roughly 90 and
   fully open) fixes sign conventions per device.
3. Lid switch. `GUID_LIDSWITCH_STATE_CHANGE` power notifications give only open or
   closed. The effect plays on a fixed `clearSeconds` timeline. The settings window
   says "timed mode: this laptop has no angle sensor".

Tiers 1 and 2 feed the laptop state machine unchanged.

## 4. Repository layout

```
hingewave/
  README.md                one page: what it is, one-line install per platform
  LICENSE                  MIT
  VERSION                  single version for all platforms, tags are v<VERSION>
  docs/design.md           this document
  core/
    effect.json            tuned defaults (section 2.5)
    shader/hingewave.glsl  reference fragment shader, commented
    reference/             Python reference implementation (motion.py, render.py)
    fixtures/*.json        angle traces with expected state, tilt, progress
    golden/*.png           reference renders of the test card at known tilt and progress
    test-card.png          procedurally generated test image
  macos/                   Swift Package, build.sh, install.sh, Casks/hingewave.rb
  android/                 Gradle project
  windows/                 .NET solution, winget manifest
  .github/workflows/       ci.yml (build and test on push), release.yml (on tag)
```

### 4.1 Core contract

Every port must:

- Load `core/effect.json` at build time (bundled as a resource) so tuning changes in
  one place.
- Pass every fixture in `core/fixtures/` through its motion model with tolerance 0.5
  degrees on tilt and 0.02 on progress at each sample time.
- Render `core/test-card.png` offscreen at each `(tilt, progress)` pair listed in
  `core/golden/index.json` and reach PSNR of at least 28 dB against the golden PNG at
  320 by 200 pixels. This catches sign errors, flipped hinges and broken blur while
  tolerating kernel differences.

The Python reference implementation is the source of truth for both. Contributors
need Python 3, NumPy and Pillow only to regenerate fixtures and goldens; users need
nothing.

## 5. macOS

Native Swift Package, no Xcode project, builds with the Command Line Tools.
Minimum macOS 14 Sonoma. Apple silicon and Intel slices.

| Component | Responsibility |
|---|---|
| `LidAngleSensor` | IOKit HID: vendor 0x05AC, usage page 0x20, usage 0x8A. Polls feature report 1 (report 7 as fallback) at 50 Hz on a background thread; two-byte little-endian degrees. No permission required. |
| `MotionModel` | Section 3, pure Swift, unit tested against `core/fixtures`. |
| `ScreenStreamer` | ScreenCaptureKit stream of the built-in display, excluding Hingewave's own windows, into IOSurface-backed Metal textures. Starts on arming, stops on idle. |
| `FoldRenderer` | One Metal fragment pass implementing section 2. Blur via a mip chain generated per frame with a blit encoder and sampled at `log2(r)` with a small disc of taps. |
| `OverlayWindow` | Borderless, click-through, all Spaces, above full-screen apps, `sharingType = .none` so it never feeds back into its own capture. Built-in display only. |
| `StatusItem` | Menu bar: current angle, Follow the lid, Preview, Launch at login (SMAppService), Quit. |

Hardware gate: the app checks for the sensor at launch. Without it (M1 MacBook Air,
13-inch M1 and M2 MacBook Pro, Intel models with a clamshell switch only) the menu
shows "No lid angle sensor on this Mac" and stays idle.

Permissions: Screen Recording only, requested on first enable with a plain
explanation. Frames stay in memory and are dropped when the effect clears.

Debug flags: `--probe` prints the angle, `--simulate-close` runs a scripted 120 to 0
to 120 sweep without a sensor, `--preview <deg>` shows one angle, `--render-check
<dir>` renders the golden set offscreen and reports PSNR.

Distribution without an Apple Developer account:

- `install.sh` fetches the release zip with curl, verifies SHA-256, replaces
  `/Applications/Hingewave.app`, clears the quarantine flag and opens the app. It
  touches nothing else: no keychain, no certificates. A curl-pipe-bash script that
  imports signing keys would cost more trust than it saves.
- Releases are signed in CI with a self-signed "Hingewave Release" certificate kept
  in repository secrets. The designated requirement then reads `identifier
  "com.antlib.hingewave" and certificate root = H"..."`, which is stable across
  releases, so the Screen Recording grant survives updates. Gatekeeper still treats
  the app as unnotarized; the installer and the cask clear the quarantine flag.
  Dev builds stay ad-hoc signed. The app asks for Screen Recording at its first
  launch, so the installer's launch shows the prompt at install time.
- Homebrew cask in `Ant-lib/homebrew-tap` with a postflight that clears the
  quarantine flag (Homebrew 6 removed the `--no-quarantine` option).
- Browser downloads are documented with the Privacy and Security "Open Anyway" path.
- The in-app Preview and the `--demo` flag fold a generated picture, so the effect
  can be seen before Screen Recording is granted.

## 6. Android

Kotlin, Gradle Kotlin DSL, minSdk 33 (AGSL `RuntimeShader`), Compose for the
settings screen. Ships first as a live wallpaper: no accessibility service, no
overlay permission, no screen capture.

| Component | Responsibility |
|---|---|
| `HingeAngleSource` | `Sensor.TYPE_HINGE_ANGLE` at `SENSOR_DELAY_GAME`; detent detection and span calibration from section 3.3. |
| `MotionModel` | Section 3, pure Kotlin, JVM unit tests against `core/fixtures`. |
| `FoldShader` | AGSL port of section 2. The picked image and its blur pyramid are pre-rendered once as bitmaps and bound as shader inputs. |
| `HingewaveWallpaperService` | Renders through `SurfaceHolder.lockHardwareCanvas` with a `RuntimeShader` paint. Redraws only while the angle is moving. |
| `Panels` | Tells inner from cover by display size, applies the per-panel mapping. |
| Settings activity | Photo picker, live preview with an angle slider, calibrate span, detent notice, Set as wallpaper. |

Compatibility: Galaxy Z Fold 8 and Pixel Fold generations report continuous angles
to apps. Galaxy Z Fold 7 and earlier, Z Flip 5 and 6, and the Z TriFold expose only
detents to third-party apps; they get the timed fallback and a clear notice. Verified
on the Android Studio fold-in emulator until a Fold 8 is available, and the README
says so.

A system-wide overlay mode (accessibility screenshot plus overlay) is a possible
later addition and is out of scope for the first release.

Distribution: signed release APK on GitHub Releases with Obtainium metadata; F-Droid
submission after the first stable release.

## 7. Windows

C# on .NET 8, target `net8.0-windows10.0.19041.0`, Windows 10 2004 or later.
Tray app with a small settings window.

| Component | Responsibility |
|---|---|
| `AngleSource` | Tiered selection from section 3.4. |
| `MotionModel` | Section 3, pure C#, xUnit tests against `core/fixtures`. |
| `DesktopCapture` | `Windows.Graphics.Capture` of the primary monitor into Direct3D 11 textures; the overlay window is excluded via `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`. |
| `FoldRenderer` | Direct3D 11 (Vortice) with an HLSL port of section 2 and a mip-chain blur. |
| `OverlayWindow` | Layered, transparent, tool window, topmost, click-through. Primary monitor only. |
| Tray | Angle and tier, Follow the lid, Preview, Start with Windows (HKCU Run key), Quit. |

Render check runs on the WARP software rasteriser so CI can verify goldens without a
GPU.

Distribution: single self-contained `hingewave.exe` on GitHub Releases, plus a winget
manifest submitted to `winget-pkgs` at the first release. Unsigned, so the README
documents the SmartScreen "More info, Run anyway" step.

## 8. Installation targets

```
macOS    curl -fsSL https://raw.githubusercontent.com/Ant-lib/hingewave/main/macos/install.sh | bash
         brew install --cask ant-lib/tap/hingewave
Windows  winget install Ant-lib.Hingewave
Android  download hingewave-<version>.apk from Releases, or add the repo in Obtainium
```

## 9. Testing

- Core: pytest over the reference implementation; regenerating fixtures and goldens
  is a script, and CI fails if committed files differ from regenerated ones.
- Each port: unit tests for the motion model against the shared fixtures; offscreen
  render check against the goldens; a scripted sensor sweep (`--simulate-close` or
  the equivalent) for the state machine end to end.
- Hardware: macOS on a 14-inch M1 Pro MacBook Pro; Android on the emulator, then a
  Galaxy Z Fold 8; Windows on a Lenovo Yoga 7i 2-in-1. The README lists what has
  been physically verified and what has not.

## 10. CI and releases

`ci.yml` runs on every push: macOS runner builds, tests and render-checks the Swift
package; Ubuntu runner builds and unit-tests the Android app; Windows runner builds,
tests and render-checks the .NET app. `release.yml` runs on tags `v*`, builds all
three, and uploads `Hingewave-mac.zip`, `Hingewave-mac-intel.zip`, `hingewave.exe`,
`hingewave-<version>.apk` and `SHA256SUMS.txt`. Asset names never change so the
installers can rely on them.

## 11. Privacy

No network access in any app. No analytics. Captured frames live in GPU memory for
the duration of a fold and are released when the effect clears. Screens the system
marks secure are simply not captured. The macOS and Windows apps explain the capture
permission in one sentence before requesting it.

## 12. Milestones

1. `v0.1.0`: core, macOS app, installer, CI. Verified on real hardware.
2. `v0.2.0`: Android live wallpaper. Emulator-verified, then Fold 8.
3. `v0.3.0`: Windows tray app with all three tiers. Verified on the Yoga.
