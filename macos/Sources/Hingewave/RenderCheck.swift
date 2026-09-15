import CoreGraphics
import Foundation
import HingewaveCore
import ImageIO
import Metal

/// Renders core/test-card.png at every entry of core/golden/index.json through
/// the Metal shader and compares with the golden PNGs by PSNR.
enum RenderCheck {
    struct Index: Decodable {
        struct Entry: Decodable {
            let file: String
            let tilt: Double
            let progress: Double
        }
        let width: Int
        let height: Int
        let minPsnrDb: Double
        let entries: [Entry]
    }

    /// Finds the repository's core directory by walking up from the working directory.
    static func locateCore(from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        var dir = start
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("core/golden/index.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return dir.appendingPathComponent("core")
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static func run(outputDir: URL, coreDir: URL?) -> Int32 {
        guard let core = coreDir ?? locateCore() else {
            print("core/ not found; run from the repository or pass --core <dir>")
            return 2
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("no Metal device")
            return 2
        }
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: core.appendingPathComponent("golden/index.json")))
            let card = try PNG.load(core.appendingPathComponent("test-card.png"))
            let source = try PNG.makeTexture(card, device: device)
            let renderer = try FoldRenderer(device: device, pixelFormat: .bgra8Unorm)

            let targetDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: index.width, height: index.height, mipmapped: false)
            targetDesc.usage = [.renderTarget, .shaderRead]
            targetDesc.storageMode = .shared
            guard let target = device.makeTexture(descriptor: targetDesc) else { return 2 }

            var failures = 0
            print("golden".padding(toLength: 16, withPad: " ", startingAt: 0) + "   tilt progress  psnr(dB)   result")
            for e in index.entries {
                renderer.render(source: source, tilt: e.tilt, progress: e.progress, into: target)
                let actual = PNG.readBack(target)
                let golden = try PNG.load(core.appendingPathComponent("golden/\(e.file)"))
                let db = PNG.psnr(actual, golden)
                try PNG.save(actual, to: outputDir.appendingPathComponent(e.file))
                let ok = db >= index.minPsnrDb
                if !ok { failures += 1 }
                let numbers = String(format: "%6.1f %8.2f %9.2f", e.tilt, e.progress, db)
                print(e.file.padding(toLength: 16, withPad: " ", startingAt: 0) + numbers + "   " + (ok ? "ok" : "FAIL"))
            }
            print("wrote actual renders to \(outputDir.path)")
            return failures == 0 ? 0 : 1
        } catch {
            print("render check failed: \(error)")
            return 2
        }
    }
}

/// Minimal PNG in/out and pixel math on 8-bit RGBA buffers.
enum PNG {
    struct Image {
        var width: Int
        var height: Int
        var rgba: [UInt8]   // row-major, 4 bytes per pixel
    }

    enum Error: Swift.Error { case load(String), save(String), texture }

    static func load(_ url: URL) throws -> Image {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw Error.load(url.path)
        }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info) else {
            throw Error.load(url.path)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Image(width: w, height: h, rgba: rgba)
    }

    static func save(_ image: Image, to url: URL) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var bytes = image.rgba
        guard let ctx = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: cs, bitmapInfo: info),
              let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Error.save(url.path)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw Error.save(url.path) }
    }

    /// Uploads RGBA pixels as a BGRA texture (the format captured frames use).
    static func makeTexture(_ image: Image, device: MTLDevice) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: image.width, height: image.height, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { throw Error.texture }
        var bgra = image.rgba
        for i in stride(from: 0, to: bgra.count, by: 4) { bgra.swapAt(i, i + 2) }
        bgra.withUnsafeBytes { ptr in
            tex.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: image.width * 4)
        }
        return tex
    }

    /// Reads a BGRA render target back into RGBA.
    static func readBack(_ texture: MTLTexture) -> Image {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        return Image(width: w, height: h, rgba: bytes)
    }

    /// PSNR over RGB channels, pixel values scaled to [0, 1].
    static func psnr(_ a: Image, _ b: Image) -> Double {
        guard a.width == b.width, a.height == b.height else { return 0 }
        var sum = 0.0
        var n = 0
        for i in stride(from: 0, to: a.rgba.count, by: 4) {
            for c in 0..<3 {
                let d = (Double(a.rgba[i + c]) - Double(b.rgba[i + c])) / 255.0
                sum += d * d
                n += 1
            }
        }
        let mse = sum / Double(n)
        return mse == 0 ? Double.infinity : 10.0 * log10(1.0 / mse)
    }
}
