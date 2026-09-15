import AppKit
import Metal
import QuartzCore

/// Borderless, click-through window covering the built-in display, drawn with Metal.
/// `sharingType = .none` keeps it out of every screen capture, including our own.
final class OverlayWindow: NSWindow {
    let metalLayer = CAMetalLayer()

    convenience init(screen: NSScreen, device: MTLDevice, capturable: Bool = false) {
        self.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.contentsScale = screen.backingScaleFactor
        metalLayer.drawableSize = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                         height: screen.frame.height * screen.backingScaleFactor)

        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = capturable ? .readOnly : .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = metalLayer
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Runs `encode` against the next drawable and presents it. Returns false if no drawable was available.
    @discardableResult
    func draw(queue: MTLCommandQueue, encode: (MTLTexture, MTLCommandBuffer) -> Void) -> Bool {
        guard let drawable = metalLayer.nextDrawable(), let cb = queue.makeCommandBuffer() else { return false }
        encode(drawable.texture, cb)
        cb.present(drawable)
        cb.commit()
        return true
    }
}
