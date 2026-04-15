import Cocoa
import ScreenCaptureKit

class AreaCaptureOverlay: NSWindow {
    typealias CompletionHandler = (NSImage?, NSRect?, CGDirectDisplayID?) -> Void

    private let completion: CompletionHandler
    private var selectionView: SelectionOverlayView!
    private var screens: [NSScreen] = []
    private var isClosed = false

    init(completion: @escaping CompletionHandler) {
        self.completion = completion

        // Create a window that spans all screens
        let fullFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }

        super.init(
            contentRect: fullFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.screens = NSScreen.screens
        // Use a high level but not .maximumWindow — leave room for Force Quit etc.
        self.level = .init(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        selectionView = SelectionOverlayView(frame: fullFrame)
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.captureRegion(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.cancel()
        }
        self.contentView = selectionView
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        // Explicitly set first responder so keyDown (Escape) works
        makeFirstResponder(selectionView)
        NSCursor.crosshair.push()
    }

    private func dismiss() {
        guard !isClosed else { return }
        isClosed = true
        NSCursor.pop()
        orderOut(nil) // Immediately remove from screen (stronger than close())
    }

    override func close() {
        dismiss()
        super.close()
    }

    private func captureRegion(_ rect: NSRect) {
        // 1. Immediately hide the overlay so it's not captured in the screenshot
        dismiss()

        // 2. Wait for the window server to fully repaint after removing our overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            // Find which screen contains the selection center
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let screen = screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main!
            let displayID = screen.displayID

            // Use ScreenCaptureKit for reliable capture
            Task {
                do {
                    let image = try await self.captureWithScreenCaptureKit(rect: rect, screen: screen)
                    await MainActor.run {
                        self.completion(image, rect, displayID)
                    }
                } catch {
                    await MainActor.run {
                        self.completion(nil, nil, nil)
                    }
                }
            }
        }
    }

    private func captureWithScreenCaptureKit(rect: NSRect, screen: NSScreen) async throws -> NSImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find the SCDisplay matching our target screen
        guard let scDisplay = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            return nil
        }

        // Include all on-screen windows (excluding SnapIt's own windows)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows.filter { $0.owningApplication?.processID != myPID }

        let filter = SCContentFilter(display: scDisplay, including: windows)
        let scale = screen.backingScaleFactor

        // Capture the full display, then crop — avoids sourceRect coordinate/mirror issues
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        if #available(macOS 14.0, *) { config.captureResolution = .best }
        config.showsCursor = false

        var fullCGImage: CGImage

        if #available(macOS 14.0, *) {
            fullCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } else {
            guard let img = try await captureFrameAsCGImage(filter: filter, config: config) else { return nil }
            fullCGImage = img
        }

        // Crop to the selection rect
        // Convert NSScreen coordinates (bottom-left origin) to pixel coordinates (top-left origin)
        let screenFrame = screen.frame
        let relX = (rect.origin.x - screenFrame.origin.x) * scale
        let relY = (screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height) * scale
        let cropRect = CGRect(x: relX, y: relY, width: rect.width * scale, height: rect.height * scale)

        guard let croppedImage = fullCGImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: croppedImage, size: rect.size)
    }

    private func captureFrameAsCGImage(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage? {
        let delegate = SingleFrameStreamDelegate()
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global())
        try await stream.startCapture()
        let sample = try await delegate.waitForFrame()
        try await stream.stopCapture()

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    private func cancel() {
        dismiss()
        completion(nil, nil, nil)
    }

    // Allow Escape to work even if the view doesn't handle it
    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Selection Overlay View

class SelectionOverlayView: NSView {
    var onSelectionComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var isDragging = false
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var mouseLocation: NSPoint = .zero

    private let coordLabel = NSTextField(labelWithString: "")
    private let dimensionLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Coordinate label (follows cursor)
        coordLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        coordLabel.textColor = .white
        coordLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        coordLabel.isBezeled = false
        coordLabel.wantsLayer = true
        coordLabel.layer?.cornerRadius = 4
        coordLabel.isHidden = true
        addSubview(coordLabel)

        // Dimension label (shows selection size)
        dimensionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        dimensionLabel.textColor = .white
        dimensionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        dimensionLabel.isBezeled = false
        dimensionLabel.wantsLayer = true
        dimensionLabel.layer?.cornerRadius = 4
        dimensionLabel.isHidden = true
        addSubview(dimensionLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateCoordLabel()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        dimensionLabel.isHidden = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        mouseLocation = currentPoint
        updateDimensionLabel()
        updateCoordLabel()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        currentPoint = convert(event.locationInWindow, from: nil)

        let rect = selectionRect
        if rect.width > 3 && rect.height > 3 {
            onSelectionComplete?(rect)
        } else {
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    // Also handle cancelOperation for Escape via responder chain
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private var selectionRect: NSRect {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        if isDragging {
            let sel = selectionRect

            // Cut out the selection area
            NSColor.clear.setFill()
            sel.fill(using: .copy)

            // Draw selection border
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: sel)
            path.lineWidth = 1.0
            path.stroke()

            // Draw dashed inner border
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let dashedPath = NSBezierPath(rect: sel.insetBy(dx: 1, dy: 1))
            dashedPath.lineWidth = 0.5
            let pattern: [CGFloat] = [4.0, 4.0]
            dashedPath.setLineDash(pattern, count: 2, phase: 0)
            dashedPath.stroke()
        }

        // Draw crosshair
        drawCrosshair()
    }

    private func drawCrosshair() {
        guard !isDragging else { return }

        NSColor.white.withAlphaComponent(0.6).setStroke()

        // Horizontal line
        let hPath = NSBezierPath()
        hPath.move(to: NSPoint(x: bounds.minX, y: mouseLocation.y))
        hPath.line(to: NSPoint(x: bounds.maxX, y: mouseLocation.y))
        hPath.lineWidth = 0.5
        hPath.stroke()

        // Vertical line
        let vPath = NSBezierPath()
        vPath.move(to: NSPoint(x: mouseLocation.x, y: bounds.minY))
        vPath.line(to: NSPoint(x: mouseLocation.x, y: bounds.maxY))
        vPath.lineWidth = 0.5
        vPath.stroke()
    }

    private func updateCoordLabel() {
        let x = Int(mouseLocation.x)
        let y = Int(bounds.height - mouseLocation.y)
        coordLabel.stringValue = "  \(x), \(y)  "
        coordLabel.sizeToFit()
        coordLabel.frame.origin = NSPoint(
            x: mouseLocation.x + 16,
            y: mouseLocation.y + 16
        )
        coordLabel.isHidden = false
    }

    private func updateDimensionLabel() {
        let sel = selectionRect
        let w = Int(sel.width)
        let h = Int(sel.height)
        dimensionLabel.stringValue = "  \(w) × \(h)  "
        dimensionLabel.sizeToFit()
        dimensionLabel.frame.origin = NSPoint(
            x: sel.midX - dimensionLabel.frame.width / 2,
            y: sel.maxY + 8
        )
    }
}

// MARK: - SCStream single-frame helper (macOS 13 fallback)

class SingleFrameStreamDelegate: NSObject, SCStreamOutput {
    private var continuation: CheckedContinuation<CMSampleBuffer, Error>?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        continuation?.resume(returning: sampleBuffer)
        continuation = nil
    }

    func waitForFrame() async throws -> CMSampleBuffer {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }
}
