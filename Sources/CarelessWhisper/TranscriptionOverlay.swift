import AppKit

final class TranscriptionOverlay {
    private let frameInterval: TimeInterval = 0.32
    private let overlayWidth: CGFloat = 220
    private let imageView = SpriteImageView()
    private var window: NSWindow?
    private var timer: Timer?
    private var frameIndex = 0
    var onClick: (() -> Void)?

    func show() {
        guard let spriteURL = Bundle.main.url(forResource: "cat-sprite", withExtension: "png"),
              let sprite = NSImage(contentsOf: spriteURL) else { return }

        if window == nil {
            let frames = splitFrames(from: sprite)
            imageView.frames = frames
            imageView.frameIndex = 0
            imageView.onClick = { [weak self] in
                self?.onClick?()
            }
            imageView.onMove = { [weak self] origin in
                self?.savePosition(origin)
            }

            let sourceFrameSize = frames.first?.size ?? NSSize(width: 1, height: 1)
            let frameWidth = max(sourceFrameSize.width, 1)
            let frameHeight = max(sourceFrameSize.height, 1)
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
            overlay.ignoresMouseEvents = false
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
        if let saved = savedPosition(for: window.frame.size), screen.visibleFrame.contains(saved) {
            window.setFrameOrigin(saved)
            return
        }

        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 10
        )
        window.setFrameOrigin(origin)
    }

    private func savePosition(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: "buddyOverlayX")
        UserDefaults.standard.set(origin.y, forKey: "buddyOverlayY")
    }

    private func savedPosition(for size: NSSize) -> NSPoint? {
        guard UserDefaults.standard.object(forKey: "buddyOverlayX") != nil,
              UserDefaults.standard.object(forKey: "buddyOverlayY") != nil else { return nil }
        let point = NSPoint(
            x: UserDefaults.standard.double(forKey: "buddyOverlayX"),
            y: UserDefaults.standard.double(forKey: "buddyOverlayY")
        )
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: point, size: size)) }) else {
            return nil
        }
        return NSPoint(
            x: min(max(point.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width),
            y: min(max(point.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - size.height)
        )
    }

    private func startAnimating() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.imageView.frameCount
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

    private func splitFrames(from sprite: NSImage) -> [NSImage] {
        guard let sheet = sprite.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return [sprite]
        }

        let frameSize = sheet.height
        guard frameSize > 0 else { return [sprite] }

        let count = max(1, sheet.width / frameSize)
        return (0..<count).compactMap { index in
            let rect = CGRect(x: index * frameSize, y: 0, width: frameSize, height: frameSize)
            guard let frame = sheet.cropping(to: rect) else { return nil }
            let image = NSImage(cgImage: frame, size: NSSize(width: frameSize, height: frameSize))
            return frameIsVisible(frame) ? image : nil
        }
    }

    private func frameIsVisible(_ frame: CGImage) -> Bool {
        guard let dataProvider = frame.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }

        let bytesPerPixel = max(frame.bitsPerPixel / 8, 1)
        guard bytesPerPixel >= 4 else { return true }

        let width = frame.width
        let height = frame.height
        let bytesPerRow = frame.bytesPerRow
        var visiblePixels = 0

        for y in 0..<height {
            let row = bytes + y * bytesPerRow
            for x in 0..<width {
                if row[x * bytesPerPixel + 3] > 8 {
                    visiblePixels += 1
                    if visiblePixels > 64 {
                        return true
                    }
                }
            }
        }

        return false
    }
}

private final class SpriteImageView: NSView {
    var frames: [NSImage] = []
    var frameCount: Int { max(frames.count, 1) }
    var frameIndex = 0
    var onClick: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?
    private var dragStartLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var didDrag = false

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartLocation, let dragStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - dragStartLocation.x, y: current.y - dragStartLocation.y)
        if abs(delta.x) > 2 || abs(delta.y) > 2 {
            didDrag = true
        }
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + delta.x, y: dragStartOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            if let origin = window?.frame.origin {
                onMove?(origin)
            }
        } else {
            onClick?()
        }
        dragStartLocation = nil
        dragStartOrigin = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !frames.isEmpty else { return }

        frames[min(frameIndex, frames.count - 1)].draw(
            in: bounds,
            from: NSRect(origin: .zero, size: frames[min(frameIndex, frames.count - 1)].size),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
