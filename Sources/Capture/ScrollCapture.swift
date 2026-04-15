import Cocoa
import ScreenCaptureKit
import Vision

class ScrollCaptureEngine {
    /// User's selection defines:
    ///  - Left/Right: strict horizontal crop boundaries
    ///  - Top: strict — everything above is excluded (browser chrome, tabs, etc.)
    ///  - Bottom: NOT a boundary — extends to the window's bottom edge
    private var frameCaptureRect: NSRect
    private let userRect: NSRect
    private let screen: NSScreen
    private var frames: [CGImage] = []
    private var isCapturing = false
    private var completion: ((NSImage?) -> Void)?
    private var progressOverlay: ScrollProgressOverlay?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(captureRect: NSRect, screen: NSScreen) {
        self.userRect = captureRect
        self.frameCaptureRect = captureRect
        self.screen = screen
    }

    func startCapture(completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
        self.frames = []
        self.isCapturing = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.stopCapture(); return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.stopCapture() }
        }

        DispatchQueue.main.async {
            self.progressOverlay = ScrollProgressOverlay()
            self.progressOverlay?.show()
            self.progressOverlay?.update(frameCount: 0, status: "Starting scroll capture...")
            self.progressOverlay?.onStop = { [weak self] in
                self?.stopCapture()
            }
        }

        Task {
            do {
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Expand bottom boundary to window's bottom (exclude dock)
                await MainActor.run { self.expandBottomToWindow() }

                // Move mouse to center and click to focus the target window
                let centerX = frameCaptureRect.midX
                let mainScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? screen.frame.height
                let centerY = mainScreenHeight - frameCaptureRect.midY

                let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                        mouseCursorPosition: CGPoint(x: centerX, y: centerY),
                                        mouseButton: .left)
                moveEvent?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 100_000_000)

                if let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                           mouseCursorPosition: CGPoint(x: centerX, y: centerY),
                                           mouseButton: .left),
                   let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                         mouseCursorPosition: CGPoint(x: centerX, y: centerY),
                                         mouseButton: .left) {
                    clickDown.post(tap: .cghidEventTap)
                    clickUp.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)

                // Capture first frame
                guard let firstFrame = try await captureSelectedArea() else {
                    await MainActor.run { self.cleanupAndComplete(nil) }
                    return
                }
                self.frames.append(firstFrame)
                await MainActor.run {
                    self.progressOverlay?.update(frameCount: 1, status: "Capturing page 1...")
                }

                // Scroll ~50% of capture height per step
                let scrollPixels = Int(frameCaptureRect.height * 0.50)
                await performScrollLoop(scrollPixels: scrollPixels, mouseX: centerX, mouseY: centerY)
            } catch {
                print("Scroll capture error: \(error)")
                await MainActor.run { self.cleanupAndComplete(nil) }
            }
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        DispatchQueue.main.async {
            self.progressOverlay?.update(frameCount: self.frames.count,
                                          status: "Stitching \(self.frames.count) frames...")
        }
        stitchAndComplete()
    }

    private func cleanupAndComplete(_ image: NSImage?) {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        progressOverlay?.dismiss()
        completion?(image)
    }

    // MARK: - Window Detection

    private func expandBottomToWindow() {
        let centerX = userRect.midX
        let centerY = userRect.midY
        let mainScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? screen.frame.height
        let cgCenterY = mainScreenHeight - centerY

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for winInfo in windowList {
            guard let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let boundsDict = winInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let winX = boundsDict["X"], let winY = boundsDict["Y"],
                  let winW = boundsDict["Width"], let winH = boundsDict["Height"] else { continue }

            let winFrame = CGRect(x: winX, y: winY, width: winW, height: winH)

            if winFrame.contains(CGPoint(x: centerX, y: cgCenterY)) {
                let winBottomMac = mainScreenHeight - (winFrame.origin.y + winFrame.height)
                let visibleBottom = screen.visibleFrame.origin.y
                let bottomEdge = max(winBottomMac, visibleBottom)
                let userTop = userRect.origin.y + userRect.height
                let newHeight = userTop - bottomEdge
                guard newHeight > 0 else { break }
                frameCaptureRect = NSRect(
                    x: userRect.origin.x,
                    y: bottomEdge,
                    width: userRect.width,
                    height: newHeight
                )
                return
            }
        }
        frameCaptureRect = userRect
    }

    // MARK: - Scroll Loop

    private func performScrollLoop(scrollPixels: Int, mouseX: CGFloat, mouseY: CGFloat) async {
        guard isCapturing else { return }

        // Send scroll event with explicit phase fields to prevent momentum
        sendScrollEvent(pixels: scrollPixels, atX: mouseX, atY: mouseY)

        // Wait for page to finish rendering
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard isCapturing else { return }

        do {
            guard let frame = try await captureSelectedArea() else { return }

            if let lastFrame = frames.last, framesAreIdentical(frame, lastFrame) {
                await MainActor.run { self.stopCapture() }
                return
            }

            frames.append(frame)
            await MainActor.run {
                self.progressOverlay?.update(frameCount: self.frames.count,
                                              status: "Capturing page \(self.frames.count)...")
            }
        } catch {
            print("Frame capture failed: \(error)")
        }

        if frames.count < 150 && isCapturing {
            await performScrollLoop(scrollPixels: scrollPixels, mouseX: mouseX, mouseY: mouseY)
        } else if isCapturing {
            await MainActor.run { self.stopCapture() }
        }
    }

    /// Send a single scroll event with momentum disabled
    private func sendScrollEvent(pixels: Int, atX x: CGFloat, atY y: CGFloat) {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 1, wheel1: -Int32(pixels), wheel2: 0, wheel3: 0) {
            event.location = CGPoint(x: x, y: y)
            // Explicitly disable momentum/gesture phases
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Screen Capture

    private func captureSelectedArea() async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows.filter { $0.owningApplication?.processID != myPID }
        let filter = SCContentFilter(display: scDisplay, including: windows)

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        if #available(macOS 14.0, *) { config.captureResolution = .best }
        config.showsCursor = false

        var fullCGImage: CGImage
        if #available(macOS 14.0, *) {
            fullCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } else {
            let delegate = SingleFrameStreamDelegate()
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global())
            try await stream.startCapture()
            let sample = try await delegate.waitForFrame()
            try await stream.stopCapture()
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext()
            guard let img = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            fullCGImage = img
        }

        let screenFrame = screen.frame
        let relX = (frameCaptureRect.origin.x - screenFrame.origin.x) * scale
        let relY = (screenFrame.height - (frameCaptureRect.origin.y - screenFrame.origin.y) - frameCaptureRect.height) * scale
        let cropRect = CGRect(x: relX, y: relY, width: frameCaptureRect.width * scale, height: frameCaptureRect.height * scale)

        return fullCGImage.cropping(to: cropRect)
    }

    // MARK: - Frame Comparison

    private func framesAreIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let aData = a.dataProvider?.data,
              let bData = b.dataProvider?.data else { return false }

        let aPtr = CFDataGetBytePtr(aData)
        let bPtr = CFDataGetBytePtr(bData)
        let length = min(CFDataGetLength(aData), CFDataGetLength(bData))

        var matchCount = 0
        var totalCount = 0
        var offset = 0
        while offset < length {
            totalCount += 1
            if aPtr?[offset] == bPtr?[offset] { matchCount += 1 }
            offset += 100
        }
        return totalCount > 0 && Double(matchCount) / Double(totalCount) > 0.99
    }

    // MARK: - Stitching with Vision Framework

    private func stitchAndComplete() {
        guard frames.count > 1 else {
            DispatchQueue.main.async {
                if let first = self.frames.first {
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                    let size = NSSize(width: CGFloat(first.width) / scale, height: CGFloat(first.height) / scale)
                    self.cleanupAndComplete(NSImage(cgImage: first, size: size))
                } else {
                    self.cleanupAndComplete(nil)
                }
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let stitched = self.stitchFrames(self.frames)
            DispatchQueue.main.async {
                self.cleanupAndComplete(stitched)
            }
        }
    }

    private func stitchFrames(_ frames: [CGImage]) -> NSImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Use Vision framework to find the exact vertical offset between consecutive frames.
        // VNTranslationalImageRegistrationRequest returns the pixel translation.
        var strips: [CGImage] = [first]
        var totalHeight = first.height

        for i in 1..<frames.count {
            let verticalShift = findVerticalShift(reference: frames[i - 1], target: frames[i])

            // verticalShift is how many pixels the content moved UP (positive = scrolled down).
            // This is the amount of NEW content at the bottom of the target frame.
            let newPixels = Int(abs(verticalShift))

            guard newPixels > 5 else { continue } // Skip if barely moved

            // The unique strip is the bottom N pixels of the target frame
            let stripY = frames[i].height - newPixels
            guard stripY >= 0 else { continue }

            if let strip = frames[i].cropping(to: CGRect(x: 0, y: stripY, width: frames[i].width, height: newPixels)) {
                strips.append(strip)
                totalHeight += newPixels
            }
        }

        // Compose final image
        guard let context = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: first.bitsPerComponent, bytesPerRow: 0,
            space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: first.bitmapInfo.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left; draw strips top-to-bottom
        var y = totalHeight
        for strip in strips {
            y -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: y, width: strip.width, height: strip.height))
        }

        guard let stitchedCG = context.makeImage() else { return nil }
        return NSImage(cgImage: stitchedCG,
                       size: NSSize(width: CGFloat(width) / scale, height: CGFloat(totalHeight) / scale))
    }

    /// Use Apple Vision framework to find the vertical pixel offset between two frames.
    /// Returns the number of pixels the content shifted (positive = content moved up = scrolled down).
    private func findVerticalShift(reference: CGImage, target: CGImage) -> CGFloat {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: target)

        let handler = VNImageRequestHandler(cgImage: reference, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Vision registration failed: \(error)")
            return 0
        }

        guard let result = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return 0
        }

        // alignmentTransform.ty is the vertical translation.
        // Positive ty = target image is shifted UP relative to reference = content scrolled down.
        return result.alignmentTransform.ty
    }
}

// MARK: - Accessibility Permission Check

func checkAccessibilityPermission() -> Bool {
    if AXIsProcessTrusted() {
        return true
    }
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    return false
}

// MARK: - Scroll Progress Overlay

class ScrollProgressOverlay: NSWindow {
    var onStop: (() -> Void)?
    private let statusLabel = NSTextField(labelWithString: "")
    private let frameCountLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton(title: "Stop & Stitch", target: nil, action: nil)

    init() {
        let width: CGFloat = 280
        let height: CGFloat = 100
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }

        let x = screen.visibleFrame.maxX - width - 20
        let y = screen.visibleFrame.maxY - height - 20

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.frame = NSRect(x: 16, y: 68, width: width - 32, height: 20)

        frameCountLabel.font = .monospacedSystemFont(ofSize: 20, weight: .bold)
        frameCountLabel.frame = NSRect(x: 16, y: 40, width: 100, height: 28)

        stopButton.bezelStyle = .rounded
        stopButton.frame = NSRect(x: width - 130, y: 12, width: 114, height: 28)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)

        visual.addSubview(statusLabel)
        visual.addSubview(frameCountLabel)
        visual.addSubview(stopButton)
        self.contentView = visual
    }

    func show() { orderFront(nil) }
    func dismiss() { orderOut(nil) }

    func update(frameCount: Int, status: String) {
        statusLabel.stringValue = status
        frameCountLabel.stringValue = "\(frameCount) pages"
    }

    @objc private func stopClicked() { onStop?() }
}
