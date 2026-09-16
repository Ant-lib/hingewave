import Foundation
import HingewaveCore
import Metal

/// One Metal pass that turns a captured picture into the folded picture.
///
/// The source texture is copied into an internal mipmapped scratch texture each
/// frame (captured frames have no mip levels), mipmaps are generated with a blit
/// encoder, and the fragment shader samples them by blur radius.
final class FoldRenderer {
    enum Error: Swift.Error { case noDevice, pipeline(String) }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pixelFormat: MTLPixelFormat
    var config: EffectConfig

    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var scratch: MTLTexture?

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, config: EffectConfig = .defaults) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.config = config
        guard let queue = device.makeCommandQueue() else { throw Error.noDevice }
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: FoldShader.source, options: nil)
        } catch {
            throw Error.pipeline("shader compile failed: \(error)")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "fold_vertex")
        desc.fragmentFunction = library.makeFunction(name: "fold_fragment")
        desc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            throw Error.pipeline("pipeline failed: \(error)")
        }

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sd.normalizedCoordinates = true
        guard let sampler = device.makeSamplerState(descriptor: sd) else { throw Error.noDevice }
        self.sampler = sampler
    }

    /// Encodes the fold of `source` into `target`. Tilt in degrees.
    func encode(source: MTLTexture, tilt: Double, progress: Double, into target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let mipped = ensureScratch(like: source)
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                      to: mipped, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.generateMipmaps(for: mipped)
            blit.endEncoding()
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var uniforms = FoldUniforms(
            tilt: Float(tilt * Double.pi / 180.0),
            progress: Float(progress),
            eyeDistance: Float(config.eyeDistance),
            maxBlurPx: Float(config.maxBlur * Double(target.height)),
            darkenGain: Float(config.darkenGain),
            blurFloor: Float(config.blurFloor),
            texSize: SIMD2<Float>(Float(source.width), Float(source.height))
        )
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(mipped, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Synchronous convenience for offscreen use.
    func render(source: MTLTexture, tilt: Double, progress: Double, into target: MTLTexture) {
        guard let cb = queue.makeCommandBuffer() else { return }
        encode(source: source, tilt: tilt, progress: progress, into: target, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
    }

    func releaseScratch() {
        scratch = nil
    }

    private func ensureScratch(like source: MTLTexture) -> MTLTexture {
        if let s = scratch, s.width == source.width, s.height == source.height, s.pixelFormat == source.pixelFormat {
            return s
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat,
                                                          width: source.width, height: source.height,
                                                          mipmapped: true)
        d.usage = [.shaderRead]
        d.storageMode = .private
        let t = device.makeTexture(descriptor: d)!
        scratch = t
        return t
    }
}
