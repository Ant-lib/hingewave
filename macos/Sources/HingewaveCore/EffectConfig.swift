import Foundation

/// Tuned effect parameters. Mirrors core/effect.json; a test proves the two are identical.
public struct EffectConfig: Codable, Equatable {
    public struct Laptop: Codable, Equatable {
        public var armDelta: Double
        public var restSeconds: Double
        public var endAngle: Double
        public var armVelocity: Double
        public init(armDelta: Double, restSeconds: Double, endAngle: Double, armVelocity: Double) {
            self.armDelta = armDelta
            self.restSeconds = restSeconds
            self.endAngle = endAngle
            self.armVelocity = armVelocity
        }
    }

    public struct Inner: Codable, Equatable {
        public var clearStart: Double
        public var clearEnd: Double
        public init(clearStart: Double, clearEnd: Double) {
            self.clearStart = clearStart
            self.clearEnd = clearEnd
        }
    }

    public struct Cover: Codable, Equatable {
        public var frostStart: Double
        public var frostEnd: Double
        public init(frostStart: Double, frostEnd: Double) {
            self.frostStart = frostStart
            self.frostEnd = frostEnd
        }
    }

    public struct Phone: Codable, Equatable {
        public var deadZone: Double
        public var inner: Inner
        public var cover: Cover
        public init(deadZone: Double, inner: Inner, cover: Cover) {
            self.deadZone = deadZone
            self.inner = inner
            self.cover = cover
        }
    }

    public var eyeDistance: Double
    public var maxBlur: Double
    public var darkenGain: Double
    public var springHz: Double
    public var stillSeconds: Double
    public var clearSeconds: Double
    public var laptop: Laptop
    public var phone: Phone

    public init(eyeDistance: Double, maxBlur: Double, darkenGain: Double, springHz: Double,
                stillSeconds: Double, clearSeconds: Double, laptop: Laptop, phone: Phone) {
        self.eyeDistance = eyeDistance
        self.maxBlur = maxBlur
        self.darkenGain = darkenGain
        self.springHz = springHz
        self.stillSeconds = stillSeconds
        self.clearSeconds = clearSeconds
        self.laptop = laptop
        self.phone = phone
    }

    /// Values copied from core/effect.json. Change them there first, then here.
    public static let defaults = EffectConfig(
        eyeDistance: 2.0,
        maxBlur: 0.036,
        darkenGain: 2.0,
        springHz: 6.0,
        stillSeconds: 2.0,
        clearSeconds: 0.6,
        laptop: Laptop(armDelta: 5.0, restSeconds: 0.3, endAngle: 8.0, armVelocity: 15.0),
        phone: Phone(
            deadZone: 6.0,
            inner: Inner(clearStart: 100.0, clearEnd: 174.0),
            cover: Cover(frostStart: 6.0, frostEnd: 26.0)
        )
    )

    public static func load(from url: URL) throws -> EffectConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EffectConfig.self, from: data)
    }
}
