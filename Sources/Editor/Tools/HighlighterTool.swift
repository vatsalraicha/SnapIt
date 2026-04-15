import Cocoa

/// Highlighter tool - semi-transparent wide stroke
struct HighlighterToolConfig {
    var widthMultiplier: CGFloat = 6.0
    var opacity: CGFloat = 0.3

    func createAnnotation(points: [NSPoint], color: NSColor, baseWidth: CGFloat) -> FreehandAnnotation {
        let annotation = FreehandAnnotation()
        annotation.points = points
        annotation.color = color
        annotation.lineWidth = baseWidth
        annotation.isHighlighter = true
        annotation.opacity = opacity
        return annotation
    }
}
