import SwiftUI
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    let hotkey: CaptureHotkey
    @ObservedObject var prefs = PreferencesManager.shared

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.hotkey = hotkey
        view.hotkeyDescription = prefs.hotkeyDescription(for: hotkey)
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.hotkeyDescription = prefs.hotkeyDescription(for: hotkey)
    }
}

class HotkeyRecorderNSView: NSView {
    var hotkey: CaptureHotkey?

    var hotkeyDescription: String = "" {
        didSet { needsDisplay = true }
    }

    private var isRecording = false
    private let label = NSTextField(labelWithString: "")

    // Monitor for key events while recording (since we may not be first responder of the app)
    private var localMonitor: Any?
    private var flagsMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isRecording {
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.borderWidth = 2
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor
            label.stringValue = "Type shortcut..."
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            label.stringValue = hotkeyDescription
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            // Clicking again while recording cancels
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        // Temporarily unregister global hotkeys so they don't fire while recording
        GlobalHotkeyManager.shared.unregisterAll()

        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)

        // Install local event monitor for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        needsDisplay = true
        stopMonitoring()

        // Re-register all hotkeys with updated preferences
        GlobalHotkeyManager.shared.registerAllHotkeys()
    }

    private func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        guard isRecording else { return }

        // Escape cancels recording
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Delete/Backspace clears the hotkey
        if event.keyCode == 51 {
            if let hotkey = hotkey {
                PreferencesManager.shared.clearHotkey(hotkey)
                hotkeyDescription = PreferencesManager.shared.hotkeyDescription(for: hotkey)
            }
            stopRecording()
            return
        }

        // Require at least one modifier key (Cmd, Ctrl, Opt) — Shift alone isn't enough
        let flags = event.modifierFlags
        let hasModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard hasModifier else { return } // Ignore plain keys without modifiers

        // Convert NSEvent modifier flags to CGEventFlags bitmask for storage
        var modifiers: UInt32 = 0
        if flags.contains(.command)  { modifiers |= UInt32(CGEventFlags.maskCommand.rawValue) }
        if flags.contains(.shift)    { modifiers |= UInt32(CGEventFlags.maskShift.rawValue) }
        if flags.contains(.option)   { modifiers |= UInt32(CGEventFlags.maskAlternate.rawValue) }
        if flags.contains(.control)  { modifiers |= UInt32(CGEventFlags.maskControl.rawValue) }

        let keyCode = UInt32(event.keyCode)

        // Save to preferences
        if let hotkey = hotkey {
            PreferencesManager.shared.setHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
            hotkeyDescription = PreferencesManager.shared.hotkeyDescription(for: hotkey)
        }

        stopRecording()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            handleRecordedKey(event)
        } else {
            super.keyDown(with: event)
        }
    }
}
