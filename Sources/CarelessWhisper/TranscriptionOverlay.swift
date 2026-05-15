import AppKit

final class TranscriptionOverlay {
    private let frameCount = 4
    private let frameInterval: TimeInterval = 0.16
    private let overlayWidth: CGFloat = 220
    private let imageView = SpriteImageView()
    private var window: NSWindow?
    private var timer: Timer?
    private var frameIndex = 0

    func show() {
        guard let sprite = NSImage(named: "cat-sprite") else { return }

        if window == nil {
            imageView.sprite = sprite
            imageView.frameCount = frameCount
            imageView.frameIndex = 0

            let frameWidth = max(sprite.size.width / CGFloat(frameCount), 1)
            let frameHeight = max(sprite.size.height, 1)
            let frameSize = NSSize(
                width: overlayWidth,
                height: overlayWidth * (frameHeight / frameWidth)
            )
            let overlay = NSWindow(
                contentRect: NSRect(origin: .zero, size: frameSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlay.contentView = imageView
            overlay.backgroundColor = .clear
            overlay.isOpaque = false
            overlay.hasShadow = false
            overlay.ignoresMouseEvents = true
            overlay.level = .statusBar
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window = overlay
        }

        positionWindow()
        window?.orderFrontRegardless()
        startAnimating()
    }

    func hide() {
        stopAnimating()
        window?.orderOut(nil)
    }

    private func positionWindow() {
        guard let screen = NSScreen.main, let window else { return }
        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 10
        )
        window.setFrameOrigin(origin)
    }

    private func startAnimating() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frameCount
            self.imageView.frameIndex = self.frameIndex
            self.imageView.needsDisplay = true
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        imageView.frameIndex = 0
        imageView.needsDisplay = true
    }
}

private final class SpriteImageView: NSView {
    var sprite: NSImage?
    var frameCount = 1
    var frameIndex = 0

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let sprite, frameCount > 0 else { return }

        let frameWidth = sprite.size.width / CGFloat(frameCount)
        let source = NSRect(
            x: frameWidth * CGFloat(frameIndex),
            y: 0,
            width: frameWidth,
            height: sprite.size.height
        )

        sprite.draw(
            in: bounds,
            from: source,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
