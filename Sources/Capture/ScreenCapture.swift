import Cocoa
import ScreenCaptureKit

class CaptureManager {
    static let shared = CaptureManager()

    private var overlayWindow: AreaCaptureOverlay?
    private var windowCaptureOverlay: WindowCaptureOverlay?
    var lastCaptureRect: NSRect?
    var lastCaptureScreenID: CGDirectDisplayID?

    // MARK: - Area Capture

    func startAreaCapture() {
        closeOverlays()
        let overlay = AreaCaptureOverlay { [weak self] image, rect, screenID in
            self?.lastCaptureRect = rect
            self?.lastCaptureScreenID = screenID
            self?.overlayWindow = nil
            if let image = image {
                // Detect window at center of selection (convert NS coords to CG top-left coords)
                var title: String?
                if let rect = rect {
                    let mainHeight = NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
                    let cgCenter = CGPoint(x: rect.midX, y: mainHeight - rect.midY)
                    title = self?.detectWindowTitle(at: cgCenter)
                }
                self?.openEditor(with: image, windowTitle: title)
            }
        }
        overlayWindow = overlay
        overlay.show()
    }

    // MARK: - Fullscreen Capture

    func startFullscreenCapture() {
        closeOverlays()
        guard let screen = screenUnderCursor() else { return }
        let windowTitle = detectFrontmostWindowTitle() ?? "Fullscreen"

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scDisplay = content.displays.first(where: { $0.displayID == screen.displayID }) else { return }

                let myPID = ProcessInfo.processInfo.processIdentifier
                let windows = content.windows.filter { $0.owningApplication?.processID != myPID }
                let filter = SCContentFilter(display: scDisplay, including: windows)

                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                if #available(macOS 14.0, *) { config.captureResolution = .best }
                config.showsCursor = false

                if #available(macOS 14.0, *) {
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let image = NSImage(cgImage: cgImage, size: screen.frame.size)
                    await MainActor.run { self.openEditor(with: image, windowTitle: windowTitle) }
                } else {
                    let delegate = SingleFrameStreamDelegate()
                    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                    try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global())
                    try await stream.startCapture()
                    let sample = try await delegate.waitForFrame()
                    try await stream.stopCapture()
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return }
                    let ciImage = CIImage(cvImageBuffer: imageBuffer)
                    let rep = NSCIImageRep(ciImage: ciImage)
                    let image = NSImage(size: screen.frame.size)
                    image.addRepresentation(rep)
                    await MainActor.run { self.openEditor(with: image, windowTitle: windowTitle) }
                }
            } catch {
                print("Fullscreen capture failed: \(error)")
            }
        }
    }

    // MARK: - Window Capture

    func startWindowCapture() {
        closeOverlays()
        let overlay = WindowCaptureOverlay { [weak self] image, windowTitle in
            self?.windowCaptureOverlay = nil
            if let image = image {
                self?.openEditor(with: image, windowTitle: windowTitle)
            }
        }
        windowCaptureOverlay = overlay
        overlay.show()
    }

    // MARK: - Scrolling Capture

    private var scrollEngine: ScrollCaptureEngine?

    func startScrollingCapture() {
        beginScrollCaptureFlow(ocrAfter: false)
    }

    // MARK: - Scrolling Capture + OCR

    func startScrollingOCRCapture() {
        beginScrollCaptureFlow(ocrAfter: true)
    }

    private func beginScrollCaptureFlow(ocrAfter: Bool) {
        closeOverlays()

        // Check accessibility permission (required for posting scroll events)
        if !checkAccessibilityPermission() {
            NotificationHelper.show(title: "Permission Required",
                                    body: "Grant Accessibility access in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }

        // Show first-use instruction dialog (like Shottr)
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "scrollCaptureInstructionShown") {
            let alert = NSAlert()
            alert.icon = NSImage(named: NSImage.applicationIconName)
            alert.messageText = "Scrolling Capture"
            alert.informativeText = "Draw the area you want to capture and let SnapIt scroll automatically for you. Don't touch your mouse or press any keys until it stops. If you want to interrupt scrolling, press Escape."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            defaults.set(true, forKey: "scrollCaptureInstructionShown")
        }

        // Use area selection to let user draw the capture boundaries
        let overlay = AreaCaptureOverlay { [weak self] _, rect, screenID in
            self?.overlayWindow = nil
            guard let rect = rect, let screenID = screenID else { return }
            guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else { return }

            // Detect window title at center of selection
            let mainHeight = NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
            let cgCenter = CGPoint(x: rect.midX, y: mainHeight - rect.midY)
            let title = self?.detectWindowTitle(at: cgCenter)

            // Start the scroll capture engine with the selected area
            self?.beginScrollCapture(rect: rect, screen: screen, ocrAfter: ocrAfter, windowTitle: title)
        }
        overlayWindow = overlay
        overlay.show()
    }

    private func beginScrollCapture(rect: NSRect, screen: NSScreen, ocrAfter: Bool, windowTitle: String? = nil) {
        let engine = ScrollCaptureEngine(captureRect: rect, screen: screen)
        scrollEngine = engine
        engine.startCapture { [weak self] image in
            self?.scrollEngine = nil
            guard let image = image else { return }

            // Save/copy silently
            self?.openEditor(with: image, windowTitle: windowTitle)

            if ocrAfter {
                TextRecognizer.shared.recognizeText(in: image) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let text):
                            ClipboardManager.copyText(text)
                            NotificationHelper.show(title: "Scroll OCR Complete", body: "\(text.count) characters copied to clipboard")
                        case .failure(let error):
                            NotificationHelper.show(title: "OCR Failed", body: error.localizedDescription)
                        }
                    }
                }
            }

            // Scrolling capture always opens editor
            self?.showEditor(with: image)
        }
    }

    // MARK: - OCR Capture

    func startOCRCapture() {
        closeOverlays()
        let overlay = AreaCaptureOverlay { [weak self] image, _, _ in
            self?.overlayWindow = nil
            guard let image = image else { return }
            TextRecognizer.shared.recognizeText(in: image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        ClipboardManager.copyText(text)
                        NotificationHelper.show(title: "Text Copied", body: String(text.prefix(200)))
                    case .failure(let error):
                        NotificationHelper.show(title: "OCR Failed", body: error.localizedDescription)
                    }
                }
            }
        }
        overlayWindow = overlay
        overlay.show()
    }

    // MARK: - Repeat Last Capture

    func repeatLastAreaCapture() {
        guard let rect = lastCaptureRect,
              let screenID = lastCaptureScreenID else {
            NotificationHelper.show(title: "No Previous Capture", body: "Perform an area capture first.")
            return
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scDisplay = content.displays.first(where: { $0.displayID == screenID }) else { return }
                let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) ?? NSScreen.main!
                let scale = screen.backingScaleFactor

                let myPID = ProcessInfo.processInfo.processIdentifier
                let windows = content.windows.filter { $0.owningApplication?.processID != myPID }
                let filter = SCContentFilter(display: scDisplay, including: windows)

                // Capture full display then crop — avoids sourceRect mirror issues
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
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return }
                    let ciImage = CIImage(cvImageBuffer: imageBuffer)
                    let ciContext = CIContext()
                    guard let img = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
                    fullCGImage = img
                }

                // Crop to the saved rect
                let screenFrame = screen.frame
                let relX = (rect.origin.x - screenFrame.origin.x) * scale
                let relY = (screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height) * scale
                let cropRect = CGRect(x: relX, y: relY, width: rect.width * scale, height: rect.height * scale)

                guard let croppedImage = fullCGImage.cropping(to: cropRect) else { return }
                let image = NSImage(cgImage: croppedImage, size: rect.size)
                let mainHeight = NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
                let cgCenter = CGPoint(x: rect.midX, y: mainHeight - rect.midY)
                let title = self.detectWindowTitle(at: cgCenter)
                await MainActor.run { self.openEditor(with: image, windowTitle: title) }
            } catch {
                print("Repeat capture failed: \(error)")
            }
        }
    }

    // MARK: - Delayed Capture

    func startDelayedCapture(seconds: Int) {
        closeOverlays()
        let countdown = CountdownOverlay(seconds: seconds) { [weak self] in
            self?.startAreaCapture()
        }
        countdown.show()
    }

    // MARK: - Capture history (for reopen)

    /// Last captured image, available for "Reopen SnapIt" to show in editor
    private(set) var lastCapturedImage: NSImage?

    // MARK: - Window Title Detection

    /// Detect the frontmost window's title (for filename). Uses the app name + window title.
    private func detectFrontmostWindowTitle() -> String? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid != myPID else { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let name = info[kCGWindowName as String] as? String ?? ""

            if !owner.isEmpty {
                return name.isEmpty ? owner : "\(owner) - \(name)"
            }
        }
        return nil
    }

    /// Detect window title at a specific screen point (top-left CG coordinates)
    private func detectWindowTitle(at point: CGPoint) -> String? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid != myPID else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }

            let bounds = CGRect(x: x, y: y, width: w, height: h)
            if bounds.contains(point) {
                let owner = info[kCGWindowOwnerName as String] as? String ?? ""
                let name = info[kCGWindowName as String] as? String ?? ""
                return name.isEmpty ? owner : "\(owner) - \(name)"
            }
        }
        return nil
    }

    // MARK: - Editor

    /// Called after every capture. Silently saves/copies, stores for reopen. No editor window.
    func openEditor(with image: NSImage, windowTitle: String? = nil) {
        lastCapturedImage = image
        let prefs = PreferencesManager.shared

        // Auto-copy to clipboard immediately after capture
        if prefs.autoCopyToClipboard {
            ClipboardManager.copyImage(image)
        }

        // Auto-save to configured folder immediately after capture
        if prefs.autoSave {
            let url = FileExporter.autoSaveURL(windowTitle: windowTitle)
            FileExporter.saveDirectly(image: image, to: url)
            NotificationHelper.show(title: "Saved", body: url.lastPathComponent)
        }

        // Silent — no editor window opens. User can reopen via menu bar.
    }

    /// Explicitly open the editor window (triggered by "Reopen SnapIt" menu item)
    func showEditor(with image: NSImage) {
        DispatchQueue.main.async {
            // Show dock icon when editor is active
            NSApp.setActivationPolicy(.regular)

            let editorWindow = EditorWindow(image: image)
            editorWindow.onClose = {
                // Hide dock icon when editor closes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !EditorWindowTracker.shared.hasOpenWindows {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
            EditorWindowTracker.shared.track(editorWindow)
            editorWindow.showWindow()
        }
    }

    /// Reopen the last capture in the editor
    func reopenLastCapture() {
        if let image = lastCapturedImage {
            showEditor(with: image)
        } else {
            NotificationHelper.show(title: "No Capture", body: "Take a screenshot first.")
        }
    }

    // MARK: - Helpers

    private func closeOverlays() {
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
        windowCaptureOverlay?.orderOut(nil)
        windowCaptureOverlay?.close()
        windowCaptureOverlay = nil
    }

    private func screenUnderCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}

// Track editor windows for dock icon management
class EditorWindowTracker {
    static let shared = EditorWindowTracker()
    private var windows: [EditorWindow] = []

    var hasOpenWindows: Bool { !windows.isEmpty }

    func track(_ window: EditorWindow) {
        windows.append(window)
    }

    func remove(_ window: EditorWindow) {
        windows.removeAll { $0 === window }
    }
}

// Helper to get display ID from NSScreen
extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

// Simple notification helper
class NotificationHelper {
    static func show(title: String, body: String) {
        DispatchQueue.main.async {
            let toast = ToastWindow(title: title, body: body)
            toast.show()
        }
    }
}

class ToastWindow: NSWindow {
    private var hideTimer: Timer?

    init(title: String, body: String) {
        let width: CGFloat = 320
        let height: CGFloat = 60
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }
        let x = screen.visibleFrame.maxX - width - 16
        let y = screen.visibleFrame.maxY - height - 16

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

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 12, y: 32, width: width - 24, height: 20)

        let bodyLabel = NSTextField(labelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 11)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.frame = NSRect(x: 12, y: 8, width: width - 24, height: 20)
        bodyLabel.lineBreakMode = .byTruncatingTail

        visual.addSubview(titleLabel)
        visual.addSubview(bodyLabel)
        self.contentView = visual
    }

    func show() {
        orderFront(nil)
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.orderOut(nil)
            }
        }
    }
}

class CountdownOverlay: NSWindow {
    private var remaining: Int
    private let completion: () -> Void
    private var timer: Timer?
    private let label = NSTextField(labelWithString: "")

    init(seconds: Int, completion: @escaping () -> Void) {
        self.remaining = seconds
        self.completion = completion

        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }

        let size: CGFloat = 120
        let x = (screen.frame.width - size) / 2
        let y = (screen.frame.height - size) / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = size / 2

        label.font = .systemFont(ofSize: 48, weight: .bold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 30, width: size, height: 60)
        label.stringValue = "\(remaining)"

        visual.addSubview(label)
        self.contentView = visual
    }

    func show() {
        orderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remaining -= 1
            if self.remaining <= 0 {
                self.timer?.invalidate()
                self.orderOut(nil)
                self.completion()
            } else {
                self.label.stringValue = "\(self.remaining)"
            }
        }
    }
}
