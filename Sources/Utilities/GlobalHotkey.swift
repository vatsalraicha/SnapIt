import Cocoa
import Carbon

/// Global hotkey registration using Carbon Event API (no external dependencies)
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    /// Map from CaptureHotkey to the action it triggers
    private let hotkeyActions: [CaptureHotkey: () -> Void] = [
        .areaCapture: { CaptureManager.shared.startAreaCapture() },
        .fullscreenCapture: { CaptureManager.shared.startFullscreenCapture() },
        .windowCapture: { CaptureManager.shared.startWindowCapture() },
        .scrollingCapture: { CaptureManager.shared.startScrollingCapture() },
        .ocrCapture: { CaptureManager.shared.startOCRCapture() },
        .repeatCapture: { CaptureManager.shared.repeatLastAreaCapture() },
    ]

    func registerAllHotkeys() {
        unregisterAll()
        installEventHandler()

        let prefs = PreferencesManager.shared

        for hotkey in CaptureHotkey.allCases {
            guard let action = hotkeyActions[hotkey] else { continue }
            let keyCode = prefs.keyCode(for: hotkey)
            let modifiers = prefs.modifiers(for: hotkey)

            // Convert CGEventFlags-style modifiers to Carbon modifiers
            let carbonMods = carbonModifiers(from: modifiers)
            register(keyCode: keyCode, modifiers: carbonMods, handler: action)
        }
    }

    /// Convert CGEventFlags bitmask to Carbon modifier bitmask
    private func carbonModifiers(from cgFlags: UInt32) -> UInt32 {
        var carbon: UInt32 = 0
        if cgFlags & UInt32(CGEventFlags.maskCommand.rawValue) != 0 { carbon |= UInt32(cmdKey) }
        if cgFlags & UInt32(CGEventFlags.maskShift.rawValue) != 0 { carbon |= UInt32(shiftKey) }
        if cgFlags & UInt32(CGEventFlags.maskAlternate.rawValue) != 0 { carbon |= UInt32(optionKey) }
        if cgFlags & UInt32(CGEventFlags.maskControl.rawValue) != 0 { carbon |= UInt32(controlKey) }
        return carbon
    }

    private func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = handler

        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x534E4150) // "SNAP"
        hotkeyID.id = id

        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                                          GetApplicationEventTarget(), 0, &hotkeyRef)
        if status == noErr {
            hotkeyRefs.append(hotkeyRef)
        } else {
            NSLog("SnapIt: Failed to register hotkey id=\(id) keyCode=\(keyCode) mods=\(modifiers) status=\(status)")
        }
    }

    private var eventHandlerInstalled = false

    private func installEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }

            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotkeyID)

            guard status == noErr else { return OSStatus(eventNotHandledErr) }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let handler = manager.handlers[hotkeyID.id] {
                DispatchQueue.main.async { handler() }
                return noErr
            }

            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, selfPtr, nil)
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }
}
