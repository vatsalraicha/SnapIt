import Cocoa

/// Step counter tool - numbered circles that auto-increment
struct StepCounterToolConfig {
    var radius: CGFloat = 14
    var startNumber: Int = 1

    func createAnnotation(at position: NSPoint, number: Int, color: NSColor) -> StepCounterAnnotation {
        let annotation = StepCounterAnnotation(position: position, number: number)
        annotation.color = color
        annotation.radius = radius
        return annotation
    }
}
