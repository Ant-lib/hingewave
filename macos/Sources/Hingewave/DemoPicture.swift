import Foundation
import Metal

/// A generated desktop-like picture for demos and previews that need no capture:
/// a soft gradient, a faint grid, a few translucent shapes and a "dock" bar.
enum DemoPicture {
    static func makeTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let w = Float(width), h = Float(height)
        for y in 0..<height {
            for x in 0..<width {
                let fx = Float(x) / w, fy = Float(y) / h
                // Diagonal gradient from deep blue to warm orange.
                var r = 0.10 + 0.80 * fx * (0.4 + 0.6 * fy)
                var g = 0.15 + 0.35 * fy + 0.20 * fx
                var b = 0.45 + 0.35 * (1 - fx) * (1 - fy)

                // Faint grid every 96 px.
                if x % 96 == 0 || y % 96 == 0 { r *= 0.85; g *= 0.85; b *= 0.85 }

                // Two soft discs.
                let d1 = hypot(fx - 0.28, (fy - 0.35) * h / w)
                let d2 = hypot(fx - 0.70, (fy - 0.60) * h / w)
                if d1 < 0.12 { let a = Float(0.55) * (1 - d1 / 0.12); r += (1 - r) * a; g += (1 - g) * a; b += (1 - b) * a }
                if d2 < 0.16 { let a = Float(0.35) * (1 - d2 / 0.16); r *= (1 - a); g += (0.9 - g) * a; b += (0.7 - b) * a }

                // Dock bar near the hinge edge.
                if fy > 0.93 && fx > 0.25 && fx < 0.75 { r = 0.92; g = 0.92; b = 0.94 }

                let i = (y * width + x) * 4
                pixels[i] = UInt8(max(0, min(255, b * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, g * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, r * 255)))
                pixels[i + 3] = 255
            }
        }
        pixels.withUnsafeBytes { ptr in
            tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: width * 4)
        }
        return tex
    }
}
