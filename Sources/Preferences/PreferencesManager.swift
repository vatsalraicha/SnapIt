import Foundation
import Carbon

enum CaptureHotkey: String, CaseIterable {
    case areaCapture = "areaCapture"
    case fullscreenCapture = "fullscreenCapture"
    case windowCapture = "windowCapture"
    case scrollingCapture = "scrollingCapture"
    case ocrCapture = "ocrCapture"
    case repeatCapture = "repeatCapture"

    var defaultKeyCode: UInt32 {
        switch self {
        case .areaCapture: return UInt32(kVK_ANSI_4)
        case .fullscreenCapture: return UInt32(kVK_ANSI_3)
        case .windowCapture: return UInt32(kVK_ANSI_W)
        case .scrollingCapture: return UInt32(kVK_ANSI_S)
        case .ocrCapture: return UInt32(kVK_ANSI_T)
        case .repeatCapture: return UInt32(kVK_ANSI_R)
        }
    }

    var defaultModifiers: UInt32 {
        return UInt32(CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
    }

    var displayName: String {
        switch self {
        case .areaCapture: return "Area Capture"
        case .fullscreenCapture: return "Fullscreen Capture"
        case .windowCapture: return "Window Capture"
        case .scrollingCapture: return "Scrolling Capture"
        case .ocrCapture: return "OCR Text Capture"
        case .repeatCapture: return "Repeat Last Capture"
        }
    }

    /// UserDefaults keys for custom hotkey storage
    var keyCodeKey: String { "hotkey_\(rawValue)_keyCode" }
    var modifiersKey: String { "hotkey_\(rawValue)_modifiers" }
}

enum EscBehavior: String, CaseIterable, Identifiable {
    case copyAndClose = "copyAndClose"
    case saveAndClose = "saveAndClose"
    case justClose = "justClose"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copyAndClose: return "Copy to clipboard and close"
        case .saveAndClose: return "Save and close"
        case .justClose: return "Just close"
        }
    }
}

enum ColorFormat: String, CaseIterable, Identifiable {
    case hexWithHash = "hexWithHash"
    case hexWithoutHash = "hexWithoutHash"
    case rgb = "rgb"
    case hsl = "hsl"
    case oklch = "oklch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hexWithHash: return "#HEX"
        case .hexWithoutHash: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .oklch: return "OKLCH"
        }
    }
}

enum WindowShadowMode: String, CaseIterable, Identifiable {
    case transparentBg = "transparentBg"
    case trimShadow = "trimShadow"
    case solidBg = "solidBg"
    case wallpaperBg = "wallpaperBg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transparentBg: return "Shadow on transparent background"
        case .trimShadow: return "Trim shadow"
        case .solidBg: return "Shadow on solid background"
        case .wallpaperBg: return "Shadow over wallpaper"
        }
    }
}

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults(suiteName: "com.snapit.preferences")!

    // General
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var defaultSaveFolder: String {
        didSet { defaults.set(defaultSaveFolder, forKey: "defaultSaveFolder") }
    }
    @Published var autoSave: Bool {
        didSet { defaults.set(autoSave, forKey: "autoSave") }
    }
    @Published var autoCopyToClipboard: Bool {
        didSet { defaults.set(autoCopyToClipboard, forKey: "autoCopyToClipboard") }
    }
    @Published var escBehavior: EscBehavior {
        didSet { defaults.set(escBehavior.rawValue, forKey: "escBehavior") }
    }

    // Appearance
    @Published var windowShadowMode: WindowShadowMode {
        didSet { defaults.set(windowShadowMode.rawValue, forKey: "windowShadowMode") }
    }
    @Published var defaultZoomFit: Bool {
        didSet { defaults.set(defaultZoomFit, forKey: "defaultZoomFit") }
    }
    @Published var annotationColor: String {
        didSet { defaults.set(annotationColor, forKey: "annotationColor") }
    }

    // Advanced
    @Published var ocrLanguages: [String] {
        didSet { defaults.set(ocrLanguages, forKey: "ocrLanguages") }
    }
    @Published var colorFormat: ColorFormat {
        didSet { defaults.set(colorFormat.rawValue, forKey: "colorFormat") }
    }
    @Published var usePhysicalPixels: Bool {
        didSet { defaults.set(usePhysicalPixels, forKey: "usePhysicalPixels") }
    }
    @Published var stripLineBreaks: Bool {
        didSet { defaults.set(stripLineBreaks, forKey: "stripLineBreaks") }
    }

    // S3 Upload
    @Published var s3Endpoint: String {
        didSet { defaults.set(s3Endpoint, forKey: "s3Endpoint") }
    }
    @Published var s3Bucket: String {
        didSet { defaults.set(s3Bucket, forKey: "s3Bucket") }
    }
    @Published var s3AccessKey: String {
        didSet { defaults.set(s3AccessKey, forKey: "s3AccessKey") }
    }
    @Published var s3SecretKey: String {
        didSet { defaults.set(s3SecretKey, forKey: "s3SecretKey") }
    }
    @Published var s3Region: String {
        didSet { defaults.set(s3Region, forKey: "s3Region") }
    }

    private init() {
        let desktopPath = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? "~/Desktop"

        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        defaultSaveFolder = defaults.string(forKey: "defaultSaveFolder") ?? desktopPath
        autoSave = defaults.bool(forKey: "autoSave")
        autoCopyToClipboard = defaults.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        escBehavior = EscBehavior(rawValue: defaults.string(forKey: "escBehavior") ?? "") ?? .copyAndClose
        windowShadowMode = WindowShadowMode(rawValue: defaults.string(forKey: "windowShadowMode") ?? "") ?? .transparentBg
        defaultZoomFit = defaults.object(forKey: "defaultZoomFit") as? Bool ?? true
        annotationColor = defaults.string(forKey: "annotationColor") ?? "#FF3B30"
        ocrLanguages = defaults.stringArray(forKey: "ocrLanguages") ?? ["en-US"]
        colorFormat = ColorFormat(rawValue: defaults.string(forKey: "colorFormat") ?? "") ?? .hexWithHash
        usePhysicalPixels = defaults.bool(forKey: "usePhysicalPixels")
        stripLineBreaks = defaults.bool(forKey: "stripLineBreaks")
        s3Endpoint = defaults.string(forKey: "s3Endpoint") ?? ""
        s3Bucket = defaults.string(forKey: "s3Bucket") ?? ""
        s3AccessKey = defaults.string(forKey: "s3AccessKey") ?? ""
        s3SecretKey = defaults.string(forKey: "s3SecretKey") ?? ""
        s3Region = defaults.string(forKey: "s3Region") ?? "us-east-1"
    }

    // MARK: - Custom Hotkey Storage

    func keyCode(for hotkey: CaptureHotkey) -> UInt32 {
        let stored = defaults.object(forKey: hotkey.keyCodeKey) as? Int
        return stored != nil ? UInt32(stored!) : hotkey.defaultKeyCode
    }

    func modifiers(for hotkey: CaptureHotkey) -> UInt32 {
        let stored = defaults.object(forKey: hotkey.modifiersKey) as? Int
        return stored != nil ? UInt32(stored!) : hotkey.defaultModifiers
    }

    func setHotkey(_ hotkey: CaptureHotkey, keyCode: UInt32, modifiers: UInt32) {
        defaults.set(Int(keyCode), forKey: hotkey.keyCodeKey)
        defaults.set(Int(modifiers), forKey: hotkey.modifiersKey)
        objectWillChange.send()
    }

    func clearHotkey(_ hotkey: CaptureHotkey) {
        defaults.removeObject(forKey: hotkey.keyCodeKey)
        defaults.removeObject(forKey: hotkey.modifiersKey)
        objectWillChange.send()
    }

    // MARK: - Hotkey Description

    func hotkeyDescription(for hotkey: CaptureHotkey) -> String {
        let kc = keyCode(for: hotkey)
        let mods = modifiers(for: hotkey)
        return Self.descriptionForHotkey(keyCode: kc, modifiers: mods)
    }

    /// Convert a keyCode + CGEventFlags-style modifiers into a readable string like "⌃⇧4"
    static func descriptionForHotkey(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(CGEventFlags.maskControl.rawValue) != 0 { parts.append("⌃") }
        if modifiers & UInt32(CGEventFlags.maskAlternate.rawValue) != 0 { parts.append("⌥") }
        if modifiers & UInt32(CGEventFlags.maskShift.rawValue) != 0 { parts.append("⇧") }
        if modifiers & UInt32(CGEventFlags.maskCommand.rawValue) != 0 { parts.append("⌘") }

        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    /// Convert a Carbon keyCode to a human-readable string
    static func keyCodeToString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "Tab", UInt32(kVK_Return): "↩",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return map[keyCode] ?? "?"
    }
}
