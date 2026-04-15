import Cocoa

/// Manages the rendering and interaction of annotation objects on the canvas.
/// The actual annotation model types are defined in CanvasView.swift.
/// This file provides additional utilities for batch operations on annotations.

class AnnotationLayer {
    var annotations: [Annotation] = []

    /// Render all annotations into a CGContext
    func render(in context: CGContext, imageSize: NSSize) {
        for annotation in annotations {
            annotation.draw(in: context, imageSize: imageSize)
        }
    }

    /// Find the topmost annotation at a given point
    func hitTest(at point: NSPoint) -> Annotation? {
        return annotations.reversed().first { $0.hitTest(point: point) }
    }

    /// Remove an annotation by ID
    func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// Duplicate an annotation with an offset
    func duplicate(_ annotation: Annotation, offset: NSPoint = NSPoint(x: 10, y: 10)) -> Annotation {
        let copy = annotation.copy()
        // Apply offset (would need type-specific handling in a full implementation)
        return copy
    }

    /// Get bounding box of all annotations
    func boundingBox() -> NSRect? {
        guard !annotations.isEmpty else { return nil }
        // Simplified: would need type-specific bounds calculation
        return nil
    }
}
