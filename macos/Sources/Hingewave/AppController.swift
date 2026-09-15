import AppKit
import HingewaveCore
import Metal

/// Glue between the lid monitor, screen capture, renderer and overlay window.
/// All members run on the main thread.
final class AppController {
    let device: MTLDevice
    let renderer: FoldRenderer
    let monitor: LidMonitor
    let capturable: Bool

    private var streamer: ScreenStreamer?
    private var window: OverlayWindow?
    private var lastState: MotionState = .idle
    private var lastOutput: MotionOutput = .idle
    private var starting = false

    /// When false the model still runs but nothing is captured or shown.
    var followLid = true {
        didSet { if !followLid { tearDown() } }
    }

    /// When set, this picture is folded instead of a live capture. Used by --demo
    /// and by the in-app preview before Screen Recording is granted.
    var staticFrame: MTLTexture?

    /// Latest sample for the menu bar.
    private(set) var lastAngle: Double = 0
    var onSample: ((LidMonitor.Sample) -> Void)?
    /// Called once a scripted source finishes and the effect has cleared.
    var onScriptFinished: (() -> Void)?
    private var scriptDone = false

    init(device: MTLDevice, source: AngleSource, reduceMotion: Bool, capturable: Bool = false) throws {
        self.device = device
        self.capturable = capturable
        renderer = try FoldRenderer(device: device, pixelFormat: .bgra8Unorm)
        monitor = LidMonitor(source: source, model: LaptopMotionModel(config: .defaults, reduceMotion: reduceMotion))
    }

    func start() {
        monitor.onSample = { [weak self] sample in self?.handle(sample) }
        monitor.start()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("screens slept")
            self?.monitor.displayOff()
            self?.tearDown()
        }
        nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // Displays changed: the built-in screen may be gone (clamshell) or resized.
            if let self, self.window != nil, Self.builtInScreen() == nil {
                Log.info("built-in display went away")
                self.monitor.displayOff()
                self.tearDown()
            }
        }
    }

    func stop() {
        monitor.stop()
        tearDown()
    }

    // MARK: Per-sample handling

    private func handle(_ sample: LidMonitor.Sample) {
        lastAngle = sample.angle
        lastOutput = sample.output
        onSample?(sample)

        let out = sample.output
        if out.state != lastState {
            Log.info(String(format: "state %@ -> %@ at %.1f deg", lastState.rawValue, out.state.rawValue, sample.smoothed))
            lastState = out.state
        }

        guard followLid else { return }

        if out.capture {
            if streamer == nil && window == nil && !starting { beginCapture() }
        } else if streamer != nil || window != nil {
            tearDown()
        }

        if out.state == .active || out.state == .clearing, let window, window.isVisible,
           let frame = staticFrame ?? streamer?.latest {
            render(frame: frame, tilt: out.tilt, progress: out.progress, into: window)
        }

        if sample.sourceFinished && out.state == .idle && !scriptDone {
            scriptDone = true
            onScriptFinished?()
        }
    }

    private func render(frame: MTLTexture, tilt: Double, progress: Double, into window: OverlayWindow) {
        window.draw(queue: renderer.queue) { target, cb in
            renderer.encode(source: frame, tilt: tilt, progress: progress, into: target, commandBuffer: cb)
        }
    }

    // MARK: Capture lifecycle

    private func beginCapture() {
        guard let screen = Self.builtInScreen(), let displayID = Self.displayID(of: screen) else {
            Log.info("no built-in display; effect skipped")
            monitor.displayOff()
            return
        }
        if let staticFrame {
            // Demo path: no capture, fold the supplied picture.
            let w = OverlayWindow(screen: screen, device: device, capturable: capturable)
            window = w
            render(frame: staticFrame, tilt: lastOutput.tilt, progress: lastOutput.progress, into: w)
            w.orderFrontRegardless()
            monitor.captureReady()
            Log.info("overlay shown (static picture)")
            return
        }
        guard ScreenStreamer.hasPermission() else {
            Log.info("screen recording permission missing; effect skipped")
            ScreenStreamer.requestPermission()
            monitor.displayOff()
            return
        }
        starting = true
        let streamer = ScreenStreamer(device: device, displayID: displayID)
        streamer.onFrame = { [weak self] _ in self?.firstFrame(from: streamer, screen: screen) }
        streamer.onStop = { [weak self] _ in
            self?.monitor.displayOff()
            self?.tearDown()
        }
        self.streamer = streamer
        Task { @MainActor in
            do {
                try await streamer.start()
            } catch {
                Log.info("capture failed: \(error)")
                self.monitor.displayOff()
                self.tearDown()
            }
            self.starting = false
        }
    }

    private func firstFrame(from streamer: ScreenStreamer, screen: NSScreen) {
        guard self.streamer === streamer, window == nil else { return }
        let w = OverlayWindow(screen: screen, device: device, capturable: capturable)
        window = w
        // Draw the first frame before showing so the window never flashes black.
        if let frame = streamer.latest {
            render(frame: frame, tilt: lastOutput.tilt, progress: lastOutput.progress, into: w)
        }
        w.orderFrontRegardless()
        monitor.captureReady()
        Log.info("overlay shown")
        // Later frames only need to be kept; rendering follows the lid samples.
        streamer.onFrame = nil
    }

    private func tearDown() {
        starting = false
        if let window {
            window.orderOut(nil)
            self.window = nil
            Log.info("overlay hidden")
        }
        streamer?.stop()
        streamer = nil
        renderer.releaseScratch()
    }

    // MARK: Displays

    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
