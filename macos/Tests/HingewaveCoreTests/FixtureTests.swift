import XCTest
@testable import HingewaveCore

/// Replays every laptop fixture in core/fixtures through the Swift motion model.
/// Phone fixtures belong to the Android port and are skipped here on purpose.
final class FixtureTests: XCTestCase {
    struct Expectation: Decodable {
        let t: Double
        let state: MotionState
        let tilt: Double
        let progress: Double
        let capture: Bool
    }

    struct Tolerance: Decodable {
        let deg: Double
        let progress: Double
    }

    struct LaptopFixture: Decodable {
        let platform: String
        let captureLatencyMs: Double
        let reduceMotion: Bool
        let samples: [[Double]]
        let expect: [Expectation]
        let tolerance: Tolerance
    }

    func laptopFixtureURLs() throws -> [URL] {
        let dir = CorePaths.coreDir.appendingPathComponent("fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return files.filter { $0.lastPathComponent.hasPrefix("laptop-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testAllLaptopFixturesReplay() throws {
        let urls = try laptopFixtureURLs()
        XCTAssertGreaterThanOrEqual(urls.count, 4, "expected laptop fixtures in core/fixtures")
        for url in urls {
            let fixture = try JSONDecoder().decode(LaptopFixture.self, from: Data(contentsOf: url))
            XCTAssertEqual(fixture.platform, "laptop")
            try replay(fixture, name: url.lastPathComponent)
        }
    }

    private func replay(_ fixture: LaptopFixture, name: String) throws {
        var model = LaptopMotionModel(config: .defaults, reduceMotion: fixture.reduceMotion)
        var armedAt: Double?
        var outputs: [Double: MotionOutput] = [:]
        let latency = fixture.captureLatencyMs / 1000.0

        for sample in fixture.samples {
            let t = sample[0], angle = sample[1]
            if let a = armedAt, t >= a + latency {
                model.captureReady(t: t)
                armedAt = nil
            }
            let out = model.feed(t: t, angle: angle)
            if out.state == .armed && armedAt == nil && !model.captureSeen {
                armedAt = t
            }
            outputs[t] = out
        }

        for e in fixture.expect {
            guard let out = outputs[e.t] else {
                XCTFail("\(name): no output at t=\(e.t)")
                continue
            }
            XCTAssertEqual(out.state, e.state, "\(name) t=\(e.t) state")
            XCTAssertEqual(out.tilt, e.tilt, accuracy: fixture.tolerance.deg, "\(name) t=\(e.t) tilt")
            XCTAssertEqual(out.progress, e.progress, accuracy: fixture.tolerance.progress, "\(name) t=\(e.t) progress")
            XCTAssertEqual(out.capture, e.capture, "\(name) t=\(e.t) capture")
        }
    }
}
