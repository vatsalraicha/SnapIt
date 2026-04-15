import Cocoa

class PinnedWindow: NSWindow {
    private let imageView: NSImageView
    private var currentImage: NSImage

    init(image: NSImage) {
        self.currentImage = image
        self.imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        // Scale down if image is too large
        let screen = NSScreen.main!
        let maxSize = NSSize(width: screen.frame.width * 0.5, height: screen.frame.height * 0.5)
        var windowSize = image.size
        if windowSize.width > maxSize.width || windowSize.height > maxSize.height {
            let scale = min(maxSize.width / windowSize.width, maxSize.height / windowSize.height)
            windowSize = NSSize(width: windowSize.width * scale, height: windowSize.height * scale)
        }

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        imageView.frame = NSRect(origin: .zero, size: windowSize)
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        self.contentView = imageView

        self.center()
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        // Scroll to resize
        let delta = event.deltaY
        let scaleFactor: CGFloat = 1.0 + delta * 0.02
        var newSize = self.frame.size
        newSize.width *= scaleFactor
        newSize.height *= scaleFactor

        // Clamp
        newSize.width = max(50, min(newSize.width, 2000))
        newSize.height = max(50, min(newSize.height, 2000))

        // Maintain aspect ratio
        let aspect = currentImage.size.width / currentImage.size.height
        newSize.height = newSize.width / aspect

        var newFrame = self.frame
        let centerX = newFrame.midX
        let centerY = newFrame.midY
        newFrame.size = newSize
        newFrame.origin.x = centerX - newSize.width / 2
        newFrame.origin.y = centerY - newSize.height / 2

        self.setFrame(newFrame, display: true, animate: false)
        imageView.frame = NSRect(origin: .zero, size: newSize)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click to close
            close()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy Image", action: #selector(copyImage), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closePinned), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: imageView)
    }

    @objc private func copyImage() {
        ClipboardManager.copyImage(currentImage)
    }

    @objc private func closePinned() {
        close()
    }
}
