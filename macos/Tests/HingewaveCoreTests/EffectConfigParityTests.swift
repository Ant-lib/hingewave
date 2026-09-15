import XCTest
@testable import HingewaveCore

/// Locates the repository's core/ directory from this test file.
enum CorePaths {
    static var coreDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HingewaveCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("core")
    }
}

final class EffectConfigParityTests: XCTestCase {
    func testSwiftDefaultsMatchEffectJSON() throws {
        let url = CorePaths.coreDir.appendingPathComponent("effect.json")
        let fromFile = try EffectConfig.load(from: url)
        XCTAssertEqual(fromFile, EffectConfig.defaults,
                       "core/effect.json and EffectConfig.defaults differ; update both together")
    }
}
