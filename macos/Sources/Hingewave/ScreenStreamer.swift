import CoreMedia
import CoreVideo
import Foundation
import Metal
import ScreenCaptureKit

/// Streams one display through ScreenCaptureKit into Metal textures.
///
/// Hingewave's own process is excluded from the filter, and the overlay window
/// additionally sets `sharingType = .none`, so the effect never feeds back into
/// its own picture. Frames stay in GPU memory and are dropped on stop.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Error: Swift.Error { case displayNotFound, textureCache, permission }

    let device: MTLDevice
    let displayID: CGDirectDisplayID
    private var stream: SCStream?
    private var textureCache: CVMetalTextureCache?
    private let outputQueue = DispatchQueue(label: "com.antlib.hingewave.capture")

    /// Latest frame and the CV texture that keeps its memory alive. Main thread only.
    private(set) var latest: MTLTexture?
    private var latestBacking: CVMetalTexture?

    /// Called on the main thread with every new frame.
    var onFrame: ((MTLTexture) -> Void)?
    /// Called on the main thread when the stream stops on its own.
    var onStop: ((Swift.Error?) -> Void)?

    init(device: MTLDevice, displayID: CGDirectDisplayID) {
        self.device = device
        self.displayID = displayID
        super.init()
    }

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start() async throws {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw Error.textureCache
        }
        textureCache = cache

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Error.displayNotFound
        }
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = CGDisplayPixelsWide(displayID)
        config.height = CGDisplayPixelsHigh(displayID)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
        Log.info("capture started \(config.width)x\(config.height)")
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task {
            try? await stream.stopCapture()
        }
        latest = nil
        latestBacking = nil
        if let cache = textureCache { CVMetalTextureCacheFlush(cache, 0) }
        Log.info("capture stopped")
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil,
                                                               .bgra8Unorm, width, height, 0, &cvTexture)
        guard result == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.latest = texture
            self.latestBacking = cvTexture
            self.onFrame?(texture)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Swift.Error) {
        Log.info("capture stopped with error: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.latest = nil
            self.latestBacking = nil
            self.onStop?(error)
        }
    }
}
