import Cocoa

enum EditorTool: String, CaseIterable {
    case select = "Select"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case oval = "Oval"
    case text = "Text"
    case freehand = "Freehand"
    case highlighter = "Highlighter"
    case spotlight = "Spotlight"
    case stepCounter = "Counter"
    case pixelate = "Pixelate"
    case ruler = "Ruler"
    case colorPicker = "Color"
    case magnifier = "Magnifier"
    case crop = "Crop"
    case backdrop = "Backdrop"

    var iconName: String {
        switch self {
        case .select: return "arrow.up.left"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        case .stepCounter: return "number.circle"
        case .pixelate: return "mosaic"
        case .ruler: return "ruler"
        case .colorPicker: return "eyedropper"
        case .magnifier: return "magnifyingglass"
        case .crop: return "crop"
        case .backdrop: return "photo.artframe"
        }
    }
}

// MARK: - Toolbar Item Identifiers

private extension NSToolbarItem.Identifier {
    // Tool groups
    static let pointerTools = NSToolbarItem.Identifier("pointerTools")
    static let drawingTools = NSToolbarItem.Identifier("drawingTools")
    static let annotationTools = NSToolbarItem.Identifier("annotationTools")
    static let measureTools = NSToolbarItem.Identifier("measureTools")
    // Separators
    static let sep1 = NSToolbarItem.Identifier("sep1")
    static let sep2 = NSToolbarItem.Identifier("sep2")
    // Color
    static let colorWell = NSToolbarItem.Identifier("colorWell")
    // Right side info
    static let infoGroup = NSToolbarItem.Identifier("infoGroup")
    // Actions
    static let undoRedo = NSToolbarItem.Identifier("undoRedo")
    static let actions = NSToolbarItem.Identifier("actions")
}

// MARK: - Editor View Controller

class EditorViewController: NSViewController, NSWindowDelegate, NSToolbarDelegate {
    let image: NSImage
    private var canvasView: CanvasView!
    private var currentTool: EditorTool = .select
    private var stepCounter: Int = 1
    private var toolButtons: [EditorTool: NSButton] = [:]
    private var colorWell: NSColorWell!
    private var dimensionLabel: NSTextField!
    private var zoomLabel: NSTextField!

    init(image: NSImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Canvas in scroll view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 20.0
        scrollView.backgroundColor = NSColor(white: 0.92, alpha: 1.0)

        canvasView = CanvasView(image: image)
        canvasView.frame = NSRect(origin: .zero, size: image.size)
        canvasView.editorVC = self
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Use a centering clip view so the image is centered when smaller than viewport
        let centeringClipView = CenteringClipView()
        centeringClipView.drawsBackground = true
        centeringClipView.backgroundColor = scrollView.backgroundColor
        scrollView.contentView = centeringClipView
        scrollView.documentView = canvasView

        // Fit to window on load
        if PreferencesManager.shared.defaultZoomFit {
            DispatchQueue.main.async {
                scrollView.magnification = self.fitScale(for: scrollView)
            }
        }

        self.view = container
    }

    private func fitScale(for scrollView: NSScrollView) -> CGFloat {
        let viewSize = scrollView.bounds.size
        let imageSize = image.size
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height) * 0.95
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .pointerTools:
            return makeToolGroup(id: itemIdentifier, tools: [.arrow, .line])
        case .drawingTools:
            return makeToolGroup(id: itemIdentifier, tools: [.rectangle, .oval, .text, .freehand, .highlighter])
        case .annotationTools:
            return makeToolGroup(id: itemIdentifier, tools: [.spotlight, .stepCounter, .pixelate])
        case .measureTools:
            return makeToolGroup(id: itemIdentifier, tools: [.ruler, .colorPicker, .crop, .backdrop])
        case .colorWell:
            return makeColorWellItem()
        case .undoRedo:
            return makeUndoRedoItem()
        case .actions:
            return makeActionsItem()
        case .infoGroup:
            return makeInfoItem()
        default:
            return nil
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .pointerTools,
            .drawingTools,
            .annotationTools,
            .measureTools,
            .colorWell,
            .flexibleSpace,
            .undoRedo,
            .actions,
            .infoGroup,
        ]
    }

    // MARK: - Toolbar Item Builders

    private func makeToolButton(_ tool: EditorTool, size: CGFloat = 26) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        btn.bezelStyle = .accessoryBarAction
        btn.image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue)
        btn.imagePosition = .imageOnly
        btn.isBordered = true
        btn.target = self
        btn.action = #selector(toolClicked(_:))
        btn.toolTip = tool.rawValue
        btn.tag = EditorTool.allCases.firstIndex(of: tool) ?? 0
        if tool == .select { btn.state = .on }
        toolButtons[tool] = btn
        return btn
    }

    private func makeToolGroup(id: NSToolbarItem.Identifier, tools: [EditorTool]) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: id)
        let buttons = tools.map { makeToolButton($0) }

        let stackView = NSStackView(views: buttons)
        stackView.spacing = 1
        stackView.orientation = .horizontal

        // Create sub-items for the group
        let subItems = tools.map { tool -> NSToolbarItem in
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("\(id.rawValue).\(tool.rawValue)"))
            item.label = tool.rawValue
            return item
        }

        group.subitems = subItems
        group.view = stackView
        group.label = ""
        return group
    }

    private func makeColorWellItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .colorWell)
        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        colorWell.color = NSColor(hex: PreferencesManager.shared.annotationColor) ?? .red
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        item.view = colorWell
        item.label = "Color"
        return item
    }

    private func makeUndoRedoItem() -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: .undoRedo)

        let undoBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        undoBtn.bezelStyle = .accessoryBarAction
        undoBtn.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoBtn.imagePosition = .imageOnly
        undoBtn.target = self
        undoBtn.action = #selector(undoClicked)
        undoBtn.toolTip = "Undo (⌘Z)"

        let redoBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        redoBtn.bezelStyle = .accessoryBarAction
        redoBtn.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoBtn.imagePosition = .imageOnly
        redoBtn.target = self
        redoBtn.action = #selector(redoClicked)
        redoBtn.toolTip = "Redo (⌘⇧Z)"

        let stack = NSStackView(views: [undoBtn, redoBtn])
        stack.spacing = 1

        let sub1 = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("undo"))
        let sub2 = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("redo"))
        group.subitems = [sub1, sub2]
        group.view = stack
        group.label = ""
        return group
    }

    private func makeActionsItem() -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: .actions)

        let actionDefs: [(icon: String, tooltip: String, sel: Selector)] = [
            ("doc.on.doc", "Copy (⌘C)", #selector(copyClicked)),
            ("square.and.arrow.down", "Save (⌘S)", #selector(saveClicked)),
            ("text.viewfinder", "OCR", #selector(ocrClicked)),
            ("pin", "Pin", #selector(pinClicked)),
            ("printer", "Print (⌘P)", #selector(printClicked)),
        ]

        var buttons: [NSButton] = []
        var subItems: [NSToolbarItem] = []
        for (i, def) in actionDefs.enumerated() {
            let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
            btn.bezelStyle = .accessoryBarAction
            btn.image = NSImage(systemSymbolName: def.icon, accessibilityDescription: def.tooltip)
            btn.imagePosition = .imageOnly
            btn.target = self
            btn.action = def.sel
            btn.toolTip = def.tooltip
            buttons.append(btn)
            subItems.append(NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("action\(i)")))
        }

        let stack = NSStackView(views: buttons)
        stack.spacing = 1
        group.subitems = subItems
        group.view = stack
        group.label = ""
        return group
    }

    private func makeInfoItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .infoGroup)

        let prefs = PreferencesManager.shared
        let pixelMultiplier = prefs.usePhysicalPixels ? Int(NSScreen.main?.backingScaleFactor ?? 2) : 1
        let w = Int(image.size.width) * pixelMultiplier
        let h = Int(image.size.height) * pixelMultiplier

        dimensionLabel = NSTextField(labelWithString: "\(w)×\(h)pt")
        dimensionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        dimensionLabel.textColor = .secondaryLabelColor
        dimensionLabel.alignment = .right

        zoomLabel = NSTextField(labelWithString: "100%")
        zoomLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        zoomLabel.textColor = .tertiaryLabelColor
        zoomLabel.alignment = .right

        let stack = NSStackView(views: [dimensionLabel, zoomLabel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 0
        stack.frame = NSRect(x: 0, y: 0, width: 80, height: 30)

        item.view = stack
        item.label = "Info"
        return item
    }

    // MARK: - Tool / Action Handlers

    @objc private func toolClicked(_ sender: NSButton) {
        let tool = EditorTool.allCases[sender.tag]
        // Clicking the active tool toggles back to select
        let effectiveTool = (tool == currentTool && tool != .select) ? .select : tool
        selectTool(effectiveTool)
        canvasView.cancelCurrentOperation()
        // Update button states
        for (t, btn) in toolButtons {
            btn.state = (t == effectiveTool) ? .on : .off
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        NotificationCenter.default.post(name: .annotationColorChanged, object: sender.color)
    }

    @objc private func undoClicked() { canvasView.undo() }
    @objc private func redoClicked() { canvasView.redo() }
    @objc private func copyClicked() { copyToClipboard() }
    @objc private func saveClicked() { saveImage() }
    @objc private func ocrClicked() { performOCR() }
    @objc private func pinClicked() { pinScreenshot() }
    @objc private func printClicked() { printImage() }

    private func selectTool(_ tool: EditorTool) {
        currentTool = tool
        canvasView.currentTool = tool
        if tool == .stepCounter {
            canvasView.stepCounterValue = stepCounter
        }
    }

    func incrementStepCounter() {
        stepCounter += 1
        canvasView.stepCounterValue = stepCounter
    }

    func switchToSelect() {
        selectTool(.select)
        for (t, btn) in toolButtons {
            btn.state = (t == .select) ? .on : .off
        }
    }

    func updateDimensionLabel(size: NSSize) {
        let prefs = PreferencesManager.shared
        let pixelMultiplier = prefs.usePhysicalPixels ? Int(NSScreen.main?.backingScaleFactor ?? 2) : 1
        let w = Int(size.width) * pixelMultiplier
        let h = Int(size.height) * pixelMultiplier
        dimensionLabel?.stringValue = "\(w)×\(h)pt"
    }

    // MARK: - Actions

    func copyToClipboard() {
        let finalImage = canvasView.renderFinalImage()
        ClipboardManager.copyImage(finalImage)
        NotificationHelper.show(title: "Copied", body: "Screenshot copied to clipboard")
    }

    private func saveImage() {
        let finalImage = canvasView.renderFinalImage()
        FileExporter.save(image: finalImage) { url in
            if let url = url {
                NotificationHelper.show(title: "Saved", body: url.lastPathComponent)
            }
        }
    }

    private func performOCR() {
        // If OCR overlay is already showing, copy the text and dismiss
        if canvasView.hasOCROverlay {
            canvasView.copyAllOCRText()
            canvasView.dismissOCROverlay()
            return
        }

        TextRecognizer.shared.recognizeTextBlocks(in: image) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let blocks):
                    self?.canvasView.showOCROverlay(blocks: blocks)
                    // Also copy all recognized text to clipboard
                    let allText = blocks.map { $0.text }.joined(separator: "\n")
                    ClipboardManager.copyText(allText)
                    NotificationHelper.show(title: "OCR Text Copied", body: "\(blocks.count) text blocks found")
                case .failure(let error):
                    NotificationHelper.show(title: "OCR Failed", body: error.localizedDescription)
                }
            }
        }
        QRDetector.shared.detectBarcodes(in: image) { result in
            DispatchQueue.main.async {
                if case .success(let barcodes) = result, !barcodes.isEmpty {
                    for barcode in barcodes {
                        let alert = NSAlert()
                        alert.messageText = "QR Code Detected"
                        alert.informativeText = barcode.payload
                        alert.addButton(withTitle: "Copy")
                        alert.addButton(withTitle: "Open URL")
                        alert.addButton(withTitle: "Dismiss")
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            ClipboardManager.copyText(barcode.payload)
                        } else if response == .alertSecondButtonReturn {
                            if let url = URL(string: barcode.payload) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addCapture() {
        view.window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startAreaCapture()
        }
    }

    private func pinScreenshot() {
        let finalImage = canvasView.renderFinalImage()
        let pinned = PinnedWindow(image: finalImage)
        pinned.show()
    }

    private func printImage() {
        let finalImage = canvasView.renderFinalImage()
        let printView = NSImageView(frame: NSRect(origin: .zero, size: finalImage.size))
        printView.image = finalImage
        let printOp = NSPrintOperation(view: printView)
        printOp.printInfo.orientation = finalImage.size.width > finalImage.size.height ? .landscape : .portrait
        printOp.run()
    }

    // MARK: - Keyboard shortcuts

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // Escape
            handleEscape()
            return
        case 36: // Return — forward to canvas (e.g. crop confirm)
            canvasView.handleReturnKey()
            return
        case 51: // Delete — forward to canvas
            canvasView.handleDeleteKey()
            return
        default:
            break
        }

        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "z":
                if flags.contains(.shift) { canvasView.redo() }
                else { canvasView.undo() }
            case "c": copyToClipboard()
            case "s": saveImage()
            case "p": printImage()
            case "0":
                if let sv = canvasView.enclosingScrollView { sv.magnification = 1.0 }
            case "1":
                if let sv = canvasView.enclosingScrollView { sv.magnification = fitScale(for: sv) }
            default: super.keyDown(with: event)
            }
        } else {
            // Forward arrow keys etc. to canvas
            canvasView.handleKeyDown(with: event)
        }
    }

    private func handleEscape() {
        // If a non-select tool is active, first Esc deselects back to select
        if currentTool != .select {
            selectTool(.select)
            for (t, btn) in toolButtons {
                btn.state = (t == .select) ? .on : .off
            }
            // Clear any in-progress state on canvas
            canvasView.cancelCurrentOperation()
            return
        }

        // Already on select tool — close the editor
        switch PreferencesManager.shared.escBehavior {
        case .copyAndClose:
            copyToClipboard()
            view.window?.close()
        case .saveAndClose:
            saveImage()
            view.window?.close()
        case .justClose:
            view.window?.close()
        }
    }

    // kept for compatibility — not used by toolbar approach
    private func handleToolbarAction(_ action: ToolbarAction) {
        switch action {
        case .undo: canvasView.undo()
        case .redo: canvasView.redo()
        case .copy: copyToClipboard()
        case .save: saveImage()
        case .ocr: performOCR()
        case .addCapture: addCapture()
        case .pin: pinScreenshot()
        case .print: printImage()
        case .backdrop: selectTool(.backdrop)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Handled by EditorWindow.close()
    }
}

enum ToolbarAction {
    case undo, redo, copy, save, ocr, addCapture, pin, print, backdrop
}

// MARK: - Centering Clip View

/// A custom NSClipView that centers the document view when it's smaller than the visible area.
class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView = documentView else { return rect }

        let docFrame = documentView.frame
        // Center horizontally if document is narrower than clip view
        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        // Center vertically if document is shorter than clip view
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}
