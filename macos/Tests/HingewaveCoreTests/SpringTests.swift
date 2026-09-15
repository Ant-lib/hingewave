import XCTest
@testable import HingewaveCore

final class SpringTests: XCTestCase {
    func testSettlesOnStepWithoutOvershoot() {
        var s = Spring(hz: 6)
        s.reset(0)
        var peak = 0.0
        var x = 0.0
        var t = 0.0
        while t < 1.0 {
            x = s.step(target: 100, dt: 0.02).x
            peak = max(peak, x)
            t += 0.02
        }
        XCTAssertLessThan(abs(x - 100), 1.0)
        XCTAssertLessThanOrEqual(peak, 100 + 1e-9)
    }

    func testFrameRateIndependence() {
        var fine = Spring(hz: 6)
        var coarse = Spring(hz: 6)
        fine.reset(10)
        coarse.reset(10)
        var xFine = 0.0
        for _ in 0..<100 { xFine = fine.step(target: 50, dt: 0.01).x }
        let xCoarse = coarse.step(target: 50, dt: 1.0).x
        XCTAssertEqual(xFine, xCoarse, accuracy: 1e-6)
    }

    func testVelocityPointsTowardTarget() {
        var s = Spring(hz: 6)
        s.reset(90)
        XCTAssertLessThan(s.step(target: 0, dt: 0.02).v, 0)
    }
}
