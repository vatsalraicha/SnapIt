import Cocoa

/// Spotlight tool - darkens everything except the selected region
struct SpotlightToolConfig {
    var darkness: CGFloat = 0.6 // How dark the non-selected area is

    func createAnnotation(rect: NSRect) -> SpotlightAnnotation {
        let annotation = SpotlightAnnotation(rect: rect)
        annotation.opacity = darkness
        return annotation
    }
}
