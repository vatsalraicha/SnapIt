import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyManager: GlobalHotkeyManager!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (LSUIElement backup)
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()
        hotkeyManager = GlobalHotkeyManager.shared

        setupStatusBarActions()
        hotkeyManager.registerAllHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }

    private func setupStatusBarActions() {
        statusBarController.onReopenSnapIt = {
            CaptureManager.shared.reopenLastCapture()
        }
        statusBarController.onAreaCapture = {
            CaptureManager.shared.startAreaCapture()
        }
        statusBarController.onFullscreenCapture = {
            CaptureManager.shared.startFullscreenCapture()
        }
        statusBarController.onWindowCapture = {
            CaptureManager.shared.startWindowCapture()
        }
        statusBarController.onScrollingCapture = {
            CaptureManager.shared.startScrollingCapture()
        }
        statusBarController.onScrollingOCRCapture = {
            CaptureManager.shared.startScrollingOCRCapture()
        }
        statusBarController.onOCRCapture = {
            CaptureManager.shared.startOCRCapture()
        }
        statusBarController.onRepeatCapture = {
            CaptureManager.shared.repeatLastAreaCapture()
        }
        statusBarController.onPreferences = { [weak self] in
            self?.showPreferences()
        }
        statusBarController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func showPreferences() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapIt Preferences"
        window.contentView = NSHostingView(rootView: prefsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }
}
