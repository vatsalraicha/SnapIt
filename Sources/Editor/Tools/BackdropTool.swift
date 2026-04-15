import Cocoa

/// Backdrop tool - add gradient backgrounds behind screenshots
struct BackdropToolConfig {
    var gradient: GradientPreset = .sunset
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadowBlur: CGFloat = 20
    var shadowIntensity: CGFloat = 0.3

    enum GradientPreset: String, CaseIterable, Identifiable {
        case sunset = "Sunset"
        case ocean = "Ocean"
        case forest = "Forest"
        case lavender = "Lavender"
        case midnight = "Midnight"
        case peach = "Peach"
        case sky = "Sky"
        case custom = "Custom"

        var id: String { rawValue }

        var colors: [NSColor] {
            switch self {
            case .sunset:
                return [NSColor(hex: "#FF6B6B")!, NSColor(hex: "#FFA07A")!, NSColor(hex: "#FFD700")!]
            case .ocean:
                return [NSColor(hex: "#0077B6")!, NSColor(hex: "#00B4D8")!, NSColor(hex: "#90E0EF")!]
            case .forest:
                return [NSColor(hex: "#2D6A4F")!, NSColor(hex: "#40916C")!, NSColor(hex: "#95D5B2")!]
            case .lavender:
                return [NSColor(hex: "#7B2FBE")!, NSColor(hex: "#9B59B6")!, NSColor(hex: "#D8B4FE")!]
            case .midnight:
                return [NSColor(hex: "#0F0C29")!, NSColor(hex: "#302B63")!, NSColor(hex: "#24243E")!]
            case .peach:
                return [NSColor(hex: "#FFDAB9")!, NSColor(hex: "#FFB6C1")!, NSColor(hex: "#FFC0CB")!]
            case .sky:
                return [NSColor(hex: "#E0F7FA")!, NSColor(hex: "#B2EBF2")!, NSColor(hex: "#80DEEA")!]
            case .custom:
                return [.white, .gray]
            }
        }
    }

    func apply(to image: NSImage) -> NSImage {
        return ImageProcessing.addGradientBackground(
            to: image,
            colors: gradient.colors,
            padding: padding,
            cornerRadius: cornerRadius,
            shadowBlur: shadowBlur
        )
    }
}
