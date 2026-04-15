import Cocoa

/// Arrow tool configuration and behavior.
/// The ArrowAnnotation model is defined in CanvasView.swift.
/// This provides additional arrow-specific behavior.

struct ArrowToolConfig {
    var style: ArrowStyle = .standard
    var headSize: CGFloat = 10

    enum ArrowStyle {
        case standard    // Straight arrow
        case curved      // Curved via control point
        case superSlim   // Extra thin
    }

    /// Creates an arrow annotation configured with current settings
    func createAnnotation(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) -> ArrowAnnotation {
        let arrow = ArrowAnnotation(start: start, end: end)
        arrow.color = color
        arrow.lineWidth = lineWidth
        arrow.isSlim = (style == .superSlim)

        // For longer arrows, make them proportionally slimmer
        let length = hypot(end.x - start.x, end.y - start.y)
        if length > 200 {
            arrow.lineWidth = max(1.0, lineWidth * (200.0 / length))
        }

        return arrow
    }
}
