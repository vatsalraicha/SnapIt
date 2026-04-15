import Cocoa

class EditorToolbar: NSView {
    var onToolSelected: ((EditorTool) -> Void)?
    var onAction: ((ToolbarAction) -> Void)?

    private var toolButtons: [NSButton] = []
    private var selectedTool: EditorTool = .select
    private var colorWell: NSColorWell!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.alignment = .centerY
        addSubview(stackView)

        // Tool buttons
        let tools: [EditorTool] = [
            .select, .arrow, .line, .rectangle, .oval, .text,
            .freehand, .highlighter, .spotlight, .stepCounter,
            .pixelate, .ruler, .colorPicker, .magnifier, .crop, .backdrop
        ]

        for tool in tools {
            let button = createToolButton(tool)
            stackView.addArrangedSubview(button)
            toolButtons.append(button)
        }

        // Separator
        let sep1 = NSBox()
        sep1.boxType = .separator
        sep1.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep1.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(sep1)

        // Color well
        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        colorWell.color = NSColor(hex: PreferencesManager.shared.annotationColor) ?? .red
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.widthAnchor.constraint(equalToConstant: 28).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stackView.addArrangedSubview(colorWell)

        // Separator
        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep2.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(sep2)

        // Action buttons
        let actionButtons: [(String, ToolbarAction)] = [
            ("arrow.uturn.backward", .undo),
            ("arrow.uturn.forward", .redo),
            ("doc.on.doc", .copy),
            ("square.and.arrow.down", .save),
            ("text.viewfinder", .ocr),
            ("plus.rectangle.on.rectangle", .addCapture),
            ("pin", .pin),
            ("printer", .print),
        ]

        for (icon, action) in actionButtons {
            let btn = createActionButton(icon: icon, action: action)
            stackView.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -80),
        ])

        // Bottom border
        let border = NSBox()
        border.boxType = .separator
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func createToolButton(_ tool: EditorTool) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.tag = EditorTool.allCases.firstIndex(of: tool) ?? 0
        button.target = self
        button.action = #selector(toolButtonClicked)
        button.toolTip = tool.rawValue
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true

        if tool == .select {
            button.state = .on
        }

        return button
    }

    private func createActionButton(icon: String, action: ToolbarAction) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.tag = 1000 + actionToInt(action)
        button.target = self
        button.action = #selector(actionButtonClicked)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tool = EditorTool.allCases[sender.tag]
        selectedTool = tool

        for btn in toolButtons {
            btn.state = .off
        }
        sender.state = .on

        onToolSelected?(tool)
    }

    @objc private func actionButtonClicked(_ sender: NSButton) {
        let actionIdx = sender.tag - 1000
        let action = intToAction(actionIdx)
        onAction?(action)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        // Propagate color change to active tool
        NotificationCenter.default.post(name: .annotationColorChanged, object: sender.color)
    }

    private func actionToInt(_ action: ToolbarAction) -> Int {
        switch action {
        case .undo: return 0
        case .redo: return 1
        case .copy: return 2
        case .save: return 3
        case .ocr: return 4
        case .addCapture: return 5
        case .pin: return 6
        case .print: return 7
        case .backdrop: return 8
        }
    }

    private func intToAction(_ val: Int) -> ToolbarAction {
        switch val {
        case 0: return .undo
        case 1: return .redo
        case 2: return .copy
        case 3: return .save
        case 4: return .ocr
        case 5: return .addCapture
        case 6: return .pin
        case 7: return .print
        case 8: return .backdrop
        default: return .copy
        }
    }
}

extension Notification.Name {
    static let annotationColorChanged = Notification.Name("annotationColorChanged")
}

extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
