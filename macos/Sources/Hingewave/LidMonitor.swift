import Foundation
import HingewaveCore
import QuartzCore

/// Anything that yields a lid angle in degrees.
protocol AngleSource: AnyObject {
    func read() -> Double?
    /// True once a scripted source has played out. Real sensors never finish.
    var finished: Bool { get }
}

extension LidAngleSensor: AngleSource {
    func read() -> Double? { readDegrees() }
    var finished: Bool { false }
}

/// Plays a list of (seconds, degrees) keyframes with linear interpolation.
final class ScriptedAngleSource: AngleSource {
    let keyframes: [(t: Double, angle: Double)]
    /// The clock starts on the first read, so setup time before polling does not eat the script.
    private var started: Double?

    init(keyframes: [(t: Double, angle: Double)]) {
        self.keyframes = keyframes
    }

    /// 120 to 0 over 2 s, hold 1 s, back to 120 over 2 s, then hold 3 s for the clear.
    static func closeAndReopen() -> ScriptedAngleSource {
        ScriptedAngleSource(keyframes: [(0, 120), (0.5, 120), (2.5, 0), (3.5, 0), (5.5, 120), (8.5, 120)])
    }

    /// Quick move from 120 to `angle` and hold so the stillness clear plays.
    static func preview(angle: Double, holdSeconds: Double = 4) -> ScriptedAngleSource {
        ScriptedAngleSource(keyframes: [(0, 120), (0.3, 120), (0.8, angle), (0.8 + holdSeconds, angle)])
    }

    var elapsed: Double {
        guard let started else { return 0 }
        return CACurrentMediaTime() - started
    }

    var finished: Bool { started != nil && elapsed >= (keyframes.last?.t ?? 0) }

    func read() -> Double? {
        if started == nil { started = CACurrentMediaTime() }
        let t = elapsed
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if t <= first.t { return first.angle }
        if t >= last.t { return last.angle }
        for i in 1..<keyframes.count where t <= keyframes[i].t {
            let a = keyframes[i - 1], b = keyframes[i]
            let f = (t - a.t) / max(b.t - a.t, 1e-9)
            return a.angle + (b.angle - a.angle) * f
        }
        return last.angle
    }
}

/// Polls an angle source at a fixed rate on a background thread, runs the motion
/// model, and delivers each output on the main thread.
final class LidMonitor {
    struct Sample {
        let angle: Double
        let smoothed: Double
        let output: MotionOutput
        let sourceFinished: Bool
    }

    let source: AngleSource
    let hz: Double
    private var model: LaptopMotionModel
    private let lock = NSLock()
    private var thread: Thread?
    private var running = false

    /// Delivered on the main thread for every poll.
    var onSample: ((Sample) -> Void)?

    init(source: AngleSource, model: LaptopMotionModel, hz: Double = 50) {
        self.source = source
        self.model = model
        self.hz = hz
    }

    var reduceMotion: Bool {
        get { lock.withLock { model.reduceMotion } }
        set { lock.withLock { model.reduceMotion = newValue } }
    }

    func start() {
        guard thread == nil else { return }
        running = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "com.antlib.hingewave.lid"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        running = false
        thread = nil
    }

    func captureReady() {
        lock.withLock { model.captureReady(t: CACurrentMediaTime()) }
    }

    func displayOff() {
        lock.withLock { model.displayOff() }
    }

    private func loop() {
        let interval = 1.0 / hz
        var next = CACurrentMediaTime()
        while running {
            if let angle = source.read() {
                let now = CACurrentMediaTime()
                let (out, smoothed) = lock.withLock { () -> (MotionOutput, Double) in
                    let o = model.feed(t: now, angle: angle)
                    return (o, model.smoothedAngle)
                }
                let sample = Sample(angle: angle, smoothed: smoothed, output: out, sourceFinished: source.finished)
                DispatchQueue.main.async { [weak self] in self?.onSample?(sample) }
            }
            next += interval
            let sleep = next - CACurrentMediaTime()
            if sleep > 0 {
                Thread.sleep(forTimeInterval: sleep)
            } else {
                next = CACurrentMediaTime()
            }
        }
    }
}
