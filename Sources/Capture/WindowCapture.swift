import Cocoa
import ScreenCaptureKit

struct WindowInfo {
    let windowID: CGWindowID
    let name: String
    let ownerName: String
    let bounds: CGRect
    let layer: Int
}

class WindowCaptureOverlay: NSWindow {
    typealias CompletionHandler = (NSImage?, String?) -> Void
    typealias WindowIDHandler = (CGWindowID) -> Void

    private let completion: CompletionHandler?
    private let windowIDHandler: WindowIDHandler?
    private var highlightView: WindowHighlightView!
    private var windowList: [WindowInfo] = []

    /// Standard init — captures the selected window and returns an image
    init(completion: @escaping CompletionHandler) {
        self.completion = completion
        self.windowIDHandler = nil
        let fullFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        super.init(contentRect: fullFrame, styleMask: .borderless, backing: .buffered, defer: false)
        commonInit(captureMode: true)
    }

    /// Window-picker-only init — returns the selected window ID without capturing
    init(windowIDHandler: @escaping WindowIDHandler) {
        self.completion = nil
        self.windowIDHandler = windowIDHandler
        let fullFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        super.init(contentRect: fullFrame, styleMask: .borderless, backing: .buffered, defer: false)
        commonInit(captureMode: false)
    }

    private func commonInit(captureMode: Bool) {
        self.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.1)
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        refreshWindowList()

        let fullFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        highlightView = WindowHighlightView(frame: fullFrame)
        highlightView.onWindowSelected = { [weak self] windowID in
            if captureMode {
                self?.captureWindow(windowID)
            } else {
                self?.selectWindow(windowID)
            }
        }
        highlightView.onCancel = { [weak self] in
            self?.cancel()
        }
        highlightView.windowList = windowList
        self.contentView = highlightView
    }

    private func refreshWindowList() {
        windowList = []
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        for info in infoList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 0, h > 0 else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue } // Only normal windows

            let name = info[kCGWindowName as String] as? String ?? ""
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let bounds = CGRect(x: x, y: y, width: w, height: h)

            windowList.append(WindowInfo(
                windowID: windowID,
                name: name,
                ownerName: owner,
                bounds: bounds,
                layer: layer
            ))
        }
    }

    func show() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(highlightView)
    }

    override func close() {
        orderOut(nil)
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel() }
        else { super.keyDown(with: event) }
    }

    private func captureWindow(_ windowID: CGWindowID) {
        // Grab the window title before closing overlay
        let winInfo = windowList.first(where: { $0.windowID == windowID })
        let windowTitle: String? = {
            guard let info = winInfo else { return nil }
            return info.name.isEmpty ? info.ownerName : "\(info.ownerName) - \(info.name)"
        }()

        orderOut(nil)
        close()

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Find the SCWindow matching the selected windowID
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    await MainActor.run { self.completion?(nil, nil) }
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)

                let config = SCStreamConfiguration()
                let bounds = scWindow.frame
                // Get the screen's backing scale factor
                let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
                let scale = screen.backingScaleFactor
                config.width = Int(bounds.width * scale)
                config.height = Int(bounds.height * scale)
                if #available(macOS 14.0, *) { config.captureResolution = .best }
                config.showsCursor = false
                // Shadow trimming is handled by using desktopIndependentWindow filter
                // which excludes window shadow by default

                var image: NSImage?

                if #available(macOS 14.0, *) {
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    image = NSImage(cgImage: cgImage, size: NSSize(width: bounds.width, height: bounds.height))
                } else {
                    let delegate = SingleFrameStreamDelegate()
                    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                    try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global())
                    try await stream.startCapture()
                    let sample = try await delegate.waitForFrame()
                    try await stream.stopCapture()
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
                        await MainActor.run { self.completion?(nil, nil) }
                        return
                    }
                    let ciImage = CIImage(cvImageBuffer: imageBuffer)
                    let rep = NSCIImageRep(ciImage: ciImage)
                    let nsImage = NSImage(size: NSSize(width: bounds.width, height: bounds.height))
                    nsImage.addRepresentation(rep)
                    image = nsImage
                }

                let shadowMode = PreferencesManager.shared.windowShadowMode
                if shadowMode == .solidBg, let img = image {
                    image = self.addSolidBackground(to: img, color: .white)
                }

                await MainActor.run {
                    self.completion?(image, windowTitle)
                }
            } catch {
                print("Window capture failed: \(error)")
                await MainActor.run { self.completion?(nil, nil) }
            }
        }
    }

    private func addSolidBackground(to image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }

    private func selectWindow(_ windowID: CGWindowID) {
        orderOut(nil)
        close()
        windowIDHandler?(windowID)
    }

    private func cancel() {
        close()
        completion?(nil, nil)
    }
}

// MARK: - Window Highlight View

class WindowHighlightView: NSView {
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    var windowList: [WindowInfo] = []

    private var hoveredWindowID: CGWindowID?
    private var hoveredBounds: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        // Convert to CGDisplay coordinates (top-left origin)
        let mainHeight = NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
        let cgPoint = CGPoint(x: screenPoint.x, y: mainHeight - screenPoint.y)

        // Find window under cursor
        var foundID: CGWindowID?
        var foundBounds: CGRect = .zero
        for winfo in windowList {
            if winfo.bounds.contains(cgPoint) {
                foundID = winfo.windowID
                foundBounds = winfo.bounds
                break
            }
        }

        if foundID != hoveredWindowID {
            hoveredWindowID = foundID
            hoveredBounds = foundBounds
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let windowID = hoveredWindowID {
            onWindowSelected?(windowID)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)

        guard hoveredWindowID != nil else { return }

        // Convert CGDisplay coordinates to NSView coordinates
        let mainHeight = NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
        let nsRect = NSRect(
            x: hoveredBounds.origin.x,
            y: mainHeight - hoveredBounds.origin.y - hoveredBounds.height,
            width: hoveredBounds.width,
            height: hoveredBounds.height
        )

        // Highlight
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        nsRect.fill()

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: nsRect)
        path.lineWidth = 2.0
        path.stroke()
    }
}
