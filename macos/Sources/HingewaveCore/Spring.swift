import Foundation

/// Critically damped spring with an exact closed-form step.
/// Same formula as core/reference/hingewave_ref/spring.py.
public struct Spring {
    public let omega: Double
    public private(set) var x: Double = 0
    public private(set) var v: Double = 0

    public init(hz: Double) {
        omega = 2.0 * Double.pi * hz
    }

    public mutating func reset(_ value: Double) {
        x = value
        v = 0
    }

    @discardableResult
    public mutating func step(target: Double, dt: Double) -> (x: Double, v: Double) {
        guard dt > 0 else { return (x, v) }
        let w = omega
        let d = x - target
        let e = exp(-w * dt)
        let xNew = target + (d + (v + w * d) * dt) * e
        let vNew = (v - w * (v + w * d) * dt) * e
        x = xNew
        v = vNew
        return (x, v)
    }
}
