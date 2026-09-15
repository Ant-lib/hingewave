import Foundation

/// Motion model for laptop lids. Executable form of docs/design.md section 3.2,
/// mirroring core/reference/hingewave_ref/motion.py and verified by core/fixtures.
public enum MotionState: String, Codable {
    case idle, armed, active, clearing
}

public struct MotionOutput: Equatable {
    public var state: MotionState
    /// Degrees the panel has rotated away from the resting plane.
    public var tilt: Double
    /// 0 open, 1 fully folded.
    public var progress: Double
    /// The host should be capturing the screen.
    public var capture: Bool

    public static let idle = MotionOutput(state: .idle, tilt: 0, progress: 0, capture: false)
}

public func smoothstep(_ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    return x * x * (3 - 2 * x)
}

public struct LaptopMotionModel {
    static let stillSpeed = 2.0
    static let endMargin = 2.0
    /// Within this many degrees of the rest angle counts as reopened.
    static let reopenMargin = 2.0

    public let config: EffectConfig
    public var reduceMotion: Bool
    public private(set) var state: MotionState = .idle
    public private(set) var captureSeen = false

    private var spring: Spring
    private var lastT: Double?
    private var stillSince: Double?
    private var clearStarted: Double?
    /// Angle the lid rests at. Follows the lid whenever it has been still for
    /// restSeconds while idle, so the effect starts from wherever the lid was.
    public private(set) var restAngle: Double?
    private var restStillSince: Double?

    public init(config: EffectConfig = .defaults, reduceMotion: Bool = false) {
        self.config = config
        self.reduceMotion = reduceMotion
        self.spring = Spring(hz: config.springHz)
    }

    /// The smoothed angle after the last feed, for display.
    public var smoothedAngle: Double { spring.x }

    // MARK: Host events

    public mutating func captureReady(t: Double) {
        captureSeen = true
        if state == .armed { state = .active }
    }

    public mutating func displayOff() {
        goIdle()
    }

    // MARK: Sampling

    public mutating func feed(t: Double, angle: Double) -> MotionOutput {
        let x: Double
        let v: Double
        if let last = lastT {
            (x, v) = spring.step(target: angle, dt: t - last)
        } else {
            spring.reset(angle)
            x = angle
            v = 0
        }
        lastT = t

        let lp = config.laptop

        if state == .idle {
            if restAngle == nil { restAngle = x }
            if abs(v) < Self.stillSpeed {
                if let since = restStillSince {
                    if t - since >= lp.restSeconds { restAngle = x }
                } else {
                    restStillSince = t
                }
            } else {
                restStillSince = nil
            }
            if let rest = restAngle, rest - x >= lp.armDelta, v <= -lp.armVelocity {
                state = .armed
                captureSeen = false
                stillSince = nil
            }
        }

        if state == .armed || state == .active {
            if let rest = restAngle, x > rest - Self.reopenMargin {
                beginClearing(t: t)
            } else if abs(v) < Self.stillSpeed && x > lp.endAngle + Self.endMargin {
                if let since = stillSince {
                    if t - since >= config.stillSeconds { beginClearing(t: t) }
                } else {
                    stillSince = t
                }
            } else {
                stillSince = nil
            }
        }

        if state == .idle { return .idle }

        var (tilt, progress) = shape(x)

        if state == .clearing, let started = clearStarted {
            let k = 1.0 - (t - started) / config.clearSeconds
            if k <= 0 {
                goIdle()
                return .idle
            }
            tilt *= k
            progress *= k
        }

        return MotionOutput(state: state, tilt: tilt, progress: progress, capture: true)
    }

    // MARK: Internals

    private func shape(_ x: Double) -> (Double, Double) {
        let lp = config.laptop
        let rest = restAngle ?? x
        let tilt = reduceMotion ? 0 : max(0, rest - x)
        let progress = smoothstep((rest - x) / max(rest - lp.endAngle, 1e-6))
        return (tilt, progress)
    }

    private mutating func beginClearing(t: Double) {
        guard state != .clearing else { return }
        state = .clearing
        clearStarted = t
        stillSince = nil
    }

    private mutating func goIdle() {
        state = .idle
        stillSince = nil
        clearStarted = nil
        captureSeen = false
        // Re-anchor at the current angle so a fresh close starts from here.
        restAngle = nil
        restStillSince = nil
    }
}
