import Cocoa

/// Configuration for rectangle and oval tools
struct ShapeToolConfig {
    var isFilled: Bool = false
    var isHandDrawn: Bool = false

    func createRectAnnotation(rect: NSRect, color: NSColor, lineWidth: CGFloat) -> RectAnnotation {
        let anno = RectAnnotation(rect: rect)
        anno.color = color
        anno.lineWidth = lineWidth
        anno.isFilled = isFilled
        anno.isHandDrawn = isHandDrawn
        return anno
    }

    func createOvalAnnotation(rect: NSRect, color: NSColor, lineWidth: CGFloat) -> OvalAnnotation {
        let anno = OvalAnnotation(rect: rect)
        anno.color = color
        anno.lineWidth = lineWidth
        anno.isFilled = isFilled
        return anno
    }
}
