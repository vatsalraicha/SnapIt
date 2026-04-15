import Cocoa

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    var onReopenSnapIt: (() -> Void)?
    var onAreaCapture: (() -> Void)?
    var onFullscreenCapture: (() -> Void)?
    var onWindowCapture: (() -> Void)?
    var onScrollingCapture: (() -> Void)?
    var onScrollingOCRCapture: (() -> Void)?
    var onOCRCapture: (() -> Void)?
    var onRepeatCapture: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            } else {
                // Fallback to system symbol
                button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapIt")
                button.image?.size = NSSize(width: 18, height: 18)
            }
        }

        buildMenu()
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        let prefs = PreferencesManager.shared

        let reopenItem = NSMenuItem(title: "Reopen SnapIt", action: #selector(handleReopenSnapIt), keyEquivalent: "")
        reopenItem.target = self
        menu.addItem(reopenItem)

        menu.addItem(NSMenuItem.separator())

        let areaItem = NSMenuItem(title: "Capture Area", action: #selector(handleAreaCapture), keyEquivalent: "")
        areaItem.keyEquivalentModifierMask = []
        areaItem.target = self
        areaItem.toolTip = prefs.hotkeyDescription(for: .areaCapture)
        menu.addItem(areaItem)

        let fullscreenItem = NSMenuItem(title: "Capture Fullscreen", action: #selector(handleFullscreenCapture), keyEquivalent: "")
        fullscreenItem.target = self
        fullscreenItem.toolTip = prefs.hotkeyDescription(for: .fullscreenCapture)
        menu.addItem(fullscreenItem)

        let windowItem = NSMenuItem(title: "Capture Window", action: #selector(handleWindowCapture), keyEquivalent: "")
        windowItem.target = self
        windowItem.toolTip = prefs.hotkeyDescription(for: .windowCapture)
        menu.addItem(windowItem)

        let scrollItem = NSMenuItem(title: "Scrolling Capture", action: #selector(handleScrollingCapture), keyEquivalent: "")
        scrollItem.target = self
        scrollItem.toolTip = prefs.hotkeyDescription(for: .scrollingCapture)
        menu.addItem(scrollItem)

        let scrollOCRItem = NSMenuItem(title: "Scrolling Capture + OCR", action: #selector(handleScrollingOCRCapture), keyEquivalent: "")
        scrollOCRItem.target = self
        menu.addItem(scrollOCRItem)

        menu.addItem(NSMenuItem.separator())

        let ocrItem = NSMenuItem(title: "OCR Text Capture", action: #selector(handleOCRCapture), keyEquivalent: "")
        ocrItem.target = self
        ocrItem.toolTip = prefs.hotkeyDescription(for: .ocrCapture)
        menu.addItem(ocrItem)

        let repeatItem = NSMenuItem(title: "Repeat Last Capture", action: #selector(handleRepeatCapture), keyEquivalent: "")
        repeatItem.target = self
        menu.addItem(repeatItem)

        menu.addItem(NSMenuItem.separator())

        // Delayed capture submenu
        let delayMenu = NSMenu()
        let delay3 = NSMenuItem(title: "3 Second Delay", action: #selector(handleDelay3), keyEquivalent: "")
        delay3.target = self
        delayMenu.addItem(delay3)
        let delay5 = NSMenuItem(title: "5 Second Delay", action: #selector(handleDelay5), keyEquivalent: "")
        delay5.target = self
        delayMenu.addItem(delay5)

        let delayItem = NSMenuItem(title: "Delayed Capture", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(handlePreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(title: "About SnapIt", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SnapIt", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func handleReopenSnapIt() { onReopenSnapIt?() }
    @objc private func handleAreaCapture() { onAreaCapture?() }
    @objc private func handleFullscreenCapture() { onFullscreenCapture?() }
    @objc private func handleWindowCapture() { onWindowCapture?() }
    @objc private func handleScrollingCapture() { onScrollingCapture?() }
    @objc private func handleScrollingOCRCapture() { onScrollingOCRCapture?() }
    @objc private func handleOCRCapture() { onOCRCapture?() }
    @objc private func handleRepeatCapture() { onRepeatCapture?() }
    @objc private func handlePreferences() { onPreferences?() }
    @objc private func handleQuit() { onQuit?() }

    @objc private func handleDelay3() {
        CaptureManager.shared.startDelayedCapture(seconds: 3)
    }

    @objc private func handleDelay5() {
        CaptureManager.shared.startDelayedCapture(seconds: 5)
    }

    @objc private func handleAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "SnapIt"
        alert.informativeText = "Version \(version) (\(build))\nA powerful screenshot tool for macOS.\n\nOptimized for Apple Silicon."
        alert.icon = NSImage(named: "AppIcon")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
