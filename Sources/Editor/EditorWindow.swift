import Cocoa

class EditorWindow: NSWindow {
    let image: NSImage
    var editorVC: EditorViewController!
    var onClose: (() -> Void)?

    init(image: NSImage) {
        self.image = image

        // Size window to fit image, constrained to screen
        let screen = NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let windowSize = NSSize(
            width: visibleFrame.width * 0.9,
            height: visibleFrame.height * 0.9
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Unified title bar with toolbar — Shottr-style
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = false
        self.minSize = NSSize(width: 500, height: 300)
        self.isReleasedWhenClosed = false
        self.center()

        editorVC = EditorViewController(image: image)
        self.contentViewController = editorVC
        self.delegate = editorVC

        // Setup the NSToolbar in the title bar
        let toolbar = NSToolbar(identifier: "SnapItEditorToolbar")
        toolbar.delegate = editorVC
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        if #available(macOS 14.0, *) {
            self.toolbarStyle = .unifiedCompact
        } else {
            self.toolbarStyle = .unified
        }
        self.toolbar = toolbar

        self.registerForDraggedTypes([.png, .tiff, .fileURL])
    }

    func showWindow() {
        // Force window to 90% of screen
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let w = vf.width * 0.9
            let h = vf.height * 0.9
            let x = vf.origin.x + (vf.width - w) / 2
            let y = vf.origin.y + (vf.height - h) / 2
            self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        onClose?()
        EditorWindowTracker.shared.remove(self)
        super.close()
    }
}
