import Cocoa

// MARK: - Annotation Model

protocol Annotation: AnyObject {
    var id: UUID { get }
    var color: NSColor { get set }
    var lineWidth: CGFloat { get set }
    var opacity: CGFloat { get set }
    func draw(in context: CGContext, imageSize: NSSize)
    func hitTest(point: NSPoint) -> Bool
    func copy() -> Annotation
}

class ArrowAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0
    var startPoint: NSPoint
    var endPoint: NSPoint
    var controlPoint: NSPoint? // For curved arrows
    var isSlim: Bool = false

    init(start: NSPoint, end: NSPoint) {
        self.startPoint = start
        self.endPoint = end
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)

        let length = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        let effectiveWidth = isSlim ? max(lineWidth * 0.5, 1.0) : min(lineWidth, max(2.0, 10.0 - length / 100.0))

        context.setLineWidth(effectiveWidth)

        if let cp = controlPoint {
            // Curved arrow
            context.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
            context.addQuadCurve(to: CGPoint(x: endPoint.x, y: endPoint.y),
                                control: CGPoint(x: cp.x, y: cp.y))
            context.strokePath()
        } else {
            context.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
            context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y))
            context.strokePath()
        }

        // Arrowhead
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = max(effectiveWidth * 4, 10)
        let arrowAngle: CGFloat = .pi / 6

        let p1 = NSPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = NSPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        )

        context.move(to: CGPoint(x: endPoint.x, y: endPoint.y))
        context.addLine(to: CGPoint(x: p1.x, y: p1.y))
        context.addLine(to: CGPoint(x: p2.x, y: p2.y))
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        let threshold: CGFloat = 8
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        guard length > 0 else { return false }

        let t = max(0, min(1, ((point.x - startPoint.x) * dx + (point.y - startPoint.y) * dy) / (length * length)))
        let closest = NSPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
        return hypot(point.x - closest.x, point.y - closest.y) <= threshold
    }

    func copy() -> Annotation {
        let a = ArrowAnnotation(start: startPoint, end: endPoint)
        a.color = color; a.lineWidth = lineWidth; a.opacity = opacity
        a.controlPoint = controlPoint; a.isSlim = isSlim
        return a
    }
}

class LineAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0
    var startPoint: NSPoint
    var endPoint: NSPoint

    init(start: NSPoint, end: NSPoint) {
        self.startPoint = start
        self.endPoint = end
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
        context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y))
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        let threshold: CGFloat = 8
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        guard length > 0 else { return false }
        let t = max(0, min(1, ((point.x - startPoint.x) * dx + (point.y - startPoint.y) * dy) / (length * length)))
        let closest = NSPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
        return hypot(point.x - closest.x, point.y - closest.y) <= threshold
    }

    func copy() -> Annotation {
        let l = LineAnnotation(start: startPoint, end: endPoint)
        l.color = color; l.lineWidth = lineWidth; l.opacity = opacity
        return l
    }
}

class RectAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0
    var rect: NSRect
    var isFilled: Bool = false
    var isHandDrawn: Bool = false

    init(rect: NSRect) {
        self.rect = rect
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)

        let cgRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)

        if isFilled {
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fill(cgRect)
        }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        if isHandDrawn {
            // Slightly wobbly lines for hand-drawn feel
            let path = CGMutablePath()
            let wobble: CGFloat = 1.5
            path.move(to: CGPoint(x: cgRect.minX + CGFloat.random(in: -wobble...wobble),
                                  y: cgRect.minY + CGFloat.random(in: -wobble...wobble)))
            path.addLine(to: CGPoint(x: cgRect.maxX + CGFloat.random(in: -wobble...wobble),
                                     y: cgRect.minY + CGFloat.random(in: -wobble...wobble)))
            path.addLine(to: CGPoint(x: cgRect.maxX + CGFloat.random(in: -wobble...wobble),
                                     y: cgRect.maxY + CGFloat.random(in: -wobble...wobble)))
            path.addLine(to: CGPoint(x: cgRect.minX + CGFloat.random(in: -wobble...wobble),
                                     y: cgRect.maxY + CGFloat.random(in: -wobble...wobble)))
            path.closeSubpath()
            context.addPath(path)
        } else {
            context.addRect(cgRect)
        }
        context.strokePath()

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        return rect.insetBy(dx: -5, dy: -5).contains(point)
    }

    func copy() -> Annotation {
        let r = RectAnnotation(rect: rect)
        r.color = color; r.lineWidth = lineWidth; r.opacity = opacity
        r.isFilled = isFilled; r.isHandDrawn = isHandDrawn
        return r
    }
}

class OvalAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0
    var rect: NSRect
    var isFilled: Bool = false

    init(rect: NSRect) {
        self.rect = rect
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)
        let cgRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)

        if isFilled {
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fillEllipse(in: cgRect)
        }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: cgRect)
        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        return rect.insetBy(dx: -5, dy: -5).contains(point)
    }

    func copy() -> Annotation {
        let o = OvalAnnotation(rect: rect)
        o.color = color; o.lineWidth = lineWidth; o.opacity = opacity
        o.isFilled = isFilled
        return o
    }
}

class TextAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 0
    var opacity: CGFloat = 1.0
    var text: String
    var position: NSPoint
    var fontSize: CGFloat = 16
    var fontName: String = ".AppleSystemUIFont"

    init(text: String, position: NSPoint) {
        self.text = text
        self.position = position
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)

        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        // CoreText draws in bottom-left origin; flip locally for our flipped view
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: position.x, y: position.y + fontSize)
        CTLineDraw(line, context)

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        let approxWidth = CGFloat(text.count) * fontSize * 0.6
        let rect = NSRect(x: position.x, y: position.y - fontSize * 0.3,
                         width: approxWidth, height: fontSize * 1.3)
        return rect.contains(point)
    }

    func copy() -> Annotation {
        let t = TextAnnotation(text: text, position: position)
        t.color = color; t.opacity = opacity; t.fontSize = fontSize
        return t
    }
}

class FreehandAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var opacity: CGFloat = 1.0
    var points: [NSPoint] = []
    var isHighlighter: Bool = false

    func draw(in context: CGContext, imageSize: NSSize) {
        guard points.count > 1 else {
            // Single dot
            if let p = points.first {
                context.saveGState()
                context.setAlpha(opacity)
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: CGRect(x: p.x - lineWidth/2, y: p.y - lineWidth/2,
                                               width: lineWidth, height: lineWidth))
                context.restoreGState()
            }
            return
        }

        context.saveGState()
        if isHighlighter {
            context.setAlpha(0.3)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth * 6)
        } else {
            context.setAlpha(opacity)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 1..<points.count {
            context.addLine(to: CGPoint(x: points[i].x, y: points[i].y))
        }
        context.strokePath()

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        let threshold: CGFloat = max(lineWidth * 2, 8)
        return points.contains { hypot(point.x - $0.x, point.y - $0.y) <= threshold }
    }

    func copy() -> Annotation {
        let f = FreehandAnnotation()
        f.color = color; f.lineWidth = lineWidth; f.opacity = opacity
        f.points = points; f.isHighlighter = isHighlighter
        return f
    }
}

class SpotlightAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .black
    var lineWidth: CGFloat = 0
    var opacity: CGFloat = 0.6
    var rect: NSRect

    init(rect: NSRect) {
        self.rect = rect
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()

        // Darken everything except the selected region
        context.setFillColor(NSColor.black.withAlphaComponent(opacity).cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))

        // Clear the spotlight region
        context.setBlendMode(.clear)
        context.fill(CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        return rect.insetBy(dx: -5, dy: -5).contains(point)
    }

    func copy() -> Annotation {
        let s = SpotlightAnnotation(rect: rect)
        s.opacity = opacity
        return s
    }
}

class StepCounterAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .red
    var lineWidth: CGFloat = 0
    var opacity: CGFloat = 1.0
    var position: NSPoint
    var number: Int
    var radius: CGFloat = 14

    init(position: NSPoint, number: Int) {
        self.position = position
        self.number = number
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)

        // Circle background
        let circleRect = CGRect(x: position.x - radius, y: position.y - radius,
                                width: radius * 2, height: radius * 2)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circleRect)

        // Number text
        let text = "\(number)"
        let font = NSFont.systemFont(ofSize: radius * 1.1, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let textBounds = CTLineGetBoundsWithOptions(line, [])

        // CoreText draws in bottom-left origin; flip locally for our flipped view
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: position.x - textBounds.width / 2,
            y: position.y + textBounds.height / 2
        )
        CTLineDraw(line, context)

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        return hypot(point.x - position.x, point.y - position.y) <= radius + 5
    }

    func copy() -> Annotation {
        let s = StepCounterAnnotation(position: position, number: number)
        s.color = color; s.opacity = opacity; s.radius = radius
        return s
    }
}

class PixelateAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .clear
    var lineWidth: CGFloat = 0
    var opacity: CGFloat = 1.0
    var rect: NSRect
    var pixelSize: CGFloat = 10
    var textOnly: Bool = false
    var textBoxes: [CGRect]? // For text-only pixelation

    init(rect: NSRect) {
        self.rect = rect
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        // Pixelation is applied during renderFinalImage, not during live draw
        // Just show the region outline during editing
        context.saveGState()
        context.setStrokeColor(NSColor.systemPurple.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1.0)
        let pattern: [CGFloat] = [4, 4]
        context.setLineDash(phase: 0, lengths: pattern)
        context.addRect(CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        return rect.insetBy(dx: -5, dy: -5).contains(point)
    }

    func copy() -> Annotation {
        let p = PixelateAnnotation(rect: rect)
        p.pixelSize = pixelSize; p.textOnly = textOnly; p.textBoxes = textBoxes
        return p
    }
}

class RulerAnnotation: Annotation {
    let id = UUID()
    var color: NSColor = .systemBlue
    var lineWidth: CGFloat = 1.0
    var opacity: CGFloat = 1.0
    var startPoint: NSPoint
    var endPoint: NSPoint
    var isHorizontal: Bool

    init(start: NSPoint, end: NSPoint, horizontal: Bool) {
        self.startPoint = start
        self.endPoint = end
        self.isHorizontal = horizontal
    }

    func draw(in context: CGContext, imageSize: NSSize) {
        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)

        // Draw measurement line
        context.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
        context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y))
        context.strokePath()

        // Draw end caps
        let capSize: CGFloat = 6
        if isHorizontal {
            context.move(to: CGPoint(x: startPoint.x, y: startPoint.y - capSize))
            context.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y + capSize))
            context.move(to: CGPoint(x: endPoint.x, y: endPoint.y - capSize))
            context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y + capSize))
        } else {
            context.move(to: CGPoint(x: startPoint.x - capSize, y: startPoint.y))
            context.addLine(to: CGPoint(x: startPoint.x + capSize, y: startPoint.y))
            context.move(to: CGPoint(x: endPoint.x - capSize, y: endPoint.y))
            context.addLine(to: CGPoint(x: endPoint.x + capSize, y: endPoint.y))
        }
        context.strokePath()

        // Draw distance label
        let distance: CGFloat
        if isHorizontal {
            distance = abs(endPoint.x - startPoint.x)
        } else {
            distance = abs(endPoint.y - startPoint.y)
        }

        let text = "\(Int(distance))px"
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let textBounds = CTLineGetBoundsWithOptions(line, [])

        let midPoint = NSPoint(x: (startPoint.x + endPoint.x) / 2,
                              y: (startPoint.y + endPoint.y) / 2)
        // CoreText draws in bottom-left origin; flip locally for our flipped view
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: midPoint.x - textBounds.width / 2,
            y: midPoint.y + textBounds.height + 4
        )
        CTLineDraw(line, context)

        context.restoreGState()
    }

    func hitTest(point: NSPoint) -> Bool {
        let threshold: CGFloat = 8
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        guard length > 0 else { return false }
        let t = max(0, min(1, ((point.x - startPoint.x) * dx + (point.y - startPoint.y) * dy) / (length * length)))
        let closest = NSPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
        return hypot(point.x - closest.x, point.y - closest.y) <= threshold
    }

    func copy() -> Annotation {
        let r = RulerAnnotation(start: startPoint, end: endPoint, horizontal: isHorizontal)
        r.color = color; r.lineWidth = lineWidth; r.opacity = opacity
        return r
    }
}

// MARK: - Canvas View

class CanvasView: NSView {
    private var image: NSImage
    private var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var ocrOverlayBlocks: [RecognizedTextBlock]?

    var currentTool: EditorTool = .select
    var currentColor: NSColor = .red
    var currentLineWidth: CGFloat = 2.0
    var stepCounterValue: Int = 1
    weak var editorVC: EditorViewController?

    // Dragging state
    private var isDragging = false
    private var dragStart: NSPoint = .zero
    private var dragCurrent: NSPoint = .zero
    private var selectedAnnotation: Annotation?
    private var currentFreehand: FreehandAnnotation?
    private var isPanning = false
    private var isSpaceHeld = false

    // Selection for crop
    private var cropRect: NSRect?

    // Color picker / magnifier state
    private var magnifierPosition: NSPoint?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))

        wantsLayer = true

        NotificationCenter.default.addObserver(self, selector: #selector(colorDidChange),
                                               name: .annotationColorChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func colorDidChange(_ notification: Notification) {
        if let color = notification.object as? NSColor {
            currentColor = color
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw the screenshot image using NSImage.draw with respectFlipped
        // so it renders correctly regardless of the CGImage source orientation
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])

        // Draw annotations
        for annotation in annotations {
            annotation.draw(in: context, imageSize: image.size)
        }

        // Draw in-progress annotation
        drawInProgress(context: context)

        // Draw OCR overlay
        drawOCROverlay(context: context)

        // Draw crop rect
        if let cropRect = cropRect {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            let pattern: [CGFloat] = [6, 3]
            context.setLineDash(phase: 0, lengths: pattern)
            context.addRect(CGRect(x: cropRect.origin.x, y: cropRect.origin.y,
                                   width: cropRect.width, height: cropRect.height))
            context.strokePath()
            context.restoreGState()
        }

        // Magnifier
        if let pos = magnifierPosition, (currentTool == .magnifier || currentTool == .colorPicker) {
            drawMagnifier(context: context, at: pos)
        }
    }

    private func drawInProgress(context: CGContext) {
        guard isDragging else { return }

        let rect = NSRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )

        switch currentTool {
        case .arrow:
            let temp = ArrowAnnotation(start: dragStart, end: dragCurrent)
            temp.color = currentColor
            temp.lineWidth = currentLineWidth
            temp.draw(in: context, imageSize: image.size)

        case .line:
            let temp = LineAnnotation(start: dragStart, end: dragCurrent)
            temp.color = currentColor
            temp.lineWidth = currentLineWidth
            temp.draw(in: context, imageSize: image.size)

        case .rectangle:
            let temp = RectAnnotation(rect: rect)
            temp.color = currentColor
            temp.lineWidth = currentLineWidth
            temp.draw(in: context, imageSize: image.size)

        case .oval:
            let temp = OvalAnnotation(rect: rect)
            temp.color = currentColor
            temp.lineWidth = currentLineWidth
            temp.draw(in: context, imageSize: image.size)

        case .spotlight:
            let temp = SpotlightAnnotation(rect: rect)
            temp.draw(in: context, imageSize: image.size)

        case .pixelate:
            context.saveGState()
            context.setStrokeColor(NSColor.systemPurple.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1.5)
            context.addRect(CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))
            context.strokePath()
            context.restoreGState()

        case .crop:
            cropRect = rect
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.addRect(CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))
            context.strokePath()
            context.restoreGState()

        case .ruler:
            let isHoriz = abs(dragCurrent.x - dragStart.x) > abs(dragCurrent.y - dragStart.y)
            let temp = RulerAnnotation(start: dragStart, end: dragCurrent, horizontal: isHoriz)
            temp.draw(in: context, imageSize: image.size)

        case .freehand, .highlighter:
            if let freehand = currentFreehand {
                freehand.draw(in: context, imageSize: image.size)
            }

        default:
            break
        }
    }

    private func drawOCROverlay(context: CGContext) {
        guard let blocks = ocrOverlayBlocks else { return }

        for block in blocks {
            let rect = CGRect(
                x: block.boundingBox.origin.x * image.size.width,
                y: block.boundingBox.origin.y * image.size.height,
                width: block.boundingBox.width * image.size.width,
                height: block.boundingBox.height * image.size.height
            )

            // Note: Vision bounding box has origin at bottom-left, but our view is flipped
            let flippedY = image.size.height - rect.origin.y - rect.height
            let drawRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)

            context.saveGState()
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
            context.fill(drawRect)
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(0.5)
            context.stroke(drawRect)
            context.restoreGState()
        }
    }

    private func drawMagnifier(context: CGContext, at point: NSPoint) {
        let loupeSize: CGFloat = 120
        let zoomFactor: CGFloat = 6
        let sampleSize = loupeSize / zoomFactor

        let loupeRect = CGRect(
            x: point.x + 20,
            y: point.y - loupeSize - 20,
            width: loupeSize,
            height: loupeSize
        )

        context.saveGState()

        // Circular clip
        context.addEllipse(in: loupeRect)
        context.clip()

        // Draw zoomed image — must flip locally since CGImage.draw assumes bottom-left origin
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let sampleRect = CGRect(
                x: (point.x - sampleSize / 2) / image.size.width * CGFloat(cgImage.width),
                y: (point.y - sampleSize / 2) / image.size.height * CGFloat(cgImage.height),
                width: sampleSize / image.size.width * CGFloat(cgImage.width),
                height: sampleSize / image.size.height * CGFloat(cgImage.height)
            )
            if let cropped = cgImage.cropping(to: sampleRect) {
                context.interpolationQuality = .none
                // Flip locally for CGImage drawing in flipped context
                context.saveGState()
                context.translateBy(x: loupeRect.minX, y: loupeRect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(cropped, in: CGRect(origin: .zero, size: loupeRect.size))
                context.restoreGState()
            }
        }

        context.restoreGState()

        // Loupe border
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: loupeRect)
        context.setStrokeColor(NSColor.gray.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: loupeRect.insetBy(dx: -1, dy: -1))
        context.restoreGState()

        // Crosshair in center of loupe
        let cx = loupeRect.midX
        let cy = loupeRect.midY
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: cx - 8, y: cy))
        context.addLine(to: CGPoint(x: cx + 8, y: cy))
        context.move(to: CGPoint(x: cx, y: cy - 8))
        context.addLine(to: CGPoint(x: cx, y: cy + 8))
        context.strokePath()
        context.restoreGState()

        // Show pixel color
        if currentTool == .colorPicker {
            let pixelColor = getPixelColor(at: point)
            let format = PreferencesManager.shared.colorFormat
            let colorStr = formatColor(pixelColor, format: format)

            let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: colorStr, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            let textBounds = CTLineGetBoundsWithOptions(line, [])

            let bgRect = CGRect(
                x: loupeRect.minX,
                y: loupeRect.minY - textBounds.height - 8,
                width: max(textBounds.width + 12, loupeSize),
                height: textBounds.height + 8
            )
            context.saveGState()
            context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.fillPath()

            // CoreText draws in bottom-left origin; flip locally for our flipped view
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: bgRect.minX + 6, y: bgRect.minY + textBounds.height + 4)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isSpaceHeld {
            isPanning = true
            dragStart = event.locationInWindow
            return
        }

        // If OCR overlay is showing, check for clicks on text blocks
        if let blocks = ocrOverlayBlocks {
            for block in blocks {
                let rect = CGRect(
                    x: block.boundingBox.origin.x * image.size.width,
                    y: block.boundingBox.origin.y * image.size.height,
                    width: block.boundingBox.width * image.size.width,
                    height: block.boundingBox.height * image.size.height
                )
                let flippedY = image.size.height - rect.origin.y - rect.height
                let drawRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
                if drawRect.contains(point) {
                    ClipboardManager.copyText(block.text)
                    NotificationHelper.show(title: "Copied", body: block.text.prefix(50) + (block.text.count > 50 ? "..." : ""))
                    return
                }
            }
        }

        switch currentTool {
        case .select:
            // Hit test annotations in reverse order (topmost first)
            selectedAnnotation = annotations.reversed().first { $0.hitTest(point: point) }

        case .text:
            // Create text annotation with inline editing
            let textAnnotation = TextAnnotation(text: "", position: point)
            textAnnotation.color = currentColor
            promptForText { [weak self] text in
                guard let self = self, let text = text, !text.isEmpty else { return }
                textAnnotation.text = text
                self.saveUndoState()
                self.annotations.append(textAnnotation)
                self.needsDisplay = true
            }
            return

        case .stepCounter:
            saveUndoState()
            let counter = StepCounterAnnotation(position: point, number: stepCounterValue)
            counter.color = currentColor
            annotations.append(counter)
            editorVC?.incrementStepCounter()
            needsDisplay = true
            return

        case .freehand, .highlighter:
            let freehand = FreehandAnnotation()
            freehand.color = currentColor
            freehand.lineWidth = currentLineWidth
            freehand.isHighlighter = (currentTool == .highlighter)
            freehand.points.append(point)
            currentFreehand = freehand

        case .colorPicker:
            // TAB to copy handled in keyDown
            magnifierPosition = point
            needsDisplay = true

        case .magnifier:
            magnifierPosition = point
            needsDisplay = true

        default:
            break
        }

        dragStart = point
        dragCurrent = point
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isPanning {
            let delta = NSPoint(
                x: event.locationInWindow.x - dragStart.x,
                y: event.locationInWindow.y - dragStart.y
            )
            if let scrollView = enclosingScrollView {
                var origin = scrollView.contentView.bounds.origin
                origin.x -= delta.x
                origin.y -= delta.y
                scrollView.contentView.scroll(to: origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            dragStart = event.locationInWindow
            return
        }

        dragCurrent = point

        switch currentTool {
        case .freehand, .highlighter:
            currentFreehand?.points.append(point)

        case .colorPicker, .magnifier:
            magnifierPosition = point

        case .select:
            // Move selected annotation
            if let anno = selectedAnnotation {
                let dx = point.x - dragStart.x
                let dy = point.y - dragStart.y
                moveAnnotation(anno, dx: dx, dy: dy)
                dragStart = point
            }

        default:
            break
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        dragCurrent = point

        let rect = NSRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )

        switch currentTool {
        case .arrow:
            if rect.width > 3 || rect.height > 3 {
                saveUndoState()
                let arrow = ArrowAnnotation(start: dragStart, end: dragCurrent)
                arrow.color = currentColor
                arrow.lineWidth = currentLineWidth
                annotations.append(arrow)
            }

        case .line:
            if rect.width > 3 || rect.height > 3 {
                saveUndoState()
                let line = LineAnnotation(start: dragStart, end: dragCurrent)
                line.color = currentColor
                line.lineWidth = currentLineWidth
                annotations.append(line)
            }

        case .rectangle:
            if rect.width > 3 && rect.height > 3 {
                saveUndoState()
                let rectAnno = RectAnnotation(rect: rect)
                rectAnno.color = currentColor
                rectAnno.lineWidth = currentLineWidth
                annotations.append(rectAnno)
            }

        case .oval:
            if rect.width > 3 && rect.height > 3 {
                saveUndoState()
                let oval = OvalAnnotation(rect: rect)
                oval.color = currentColor
                oval.lineWidth = currentLineWidth
                annotations.append(oval)
            }

        case .spotlight:
            if rect.width > 3 && rect.height > 3 {
                saveUndoState()
                let spotlight = SpotlightAnnotation(rect: rect)
                annotations.append(spotlight)
            }

        case .pixelate:
            if rect.width > 3 && rect.height > 3 {
                saveUndoState()
                let pixelate = PixelateAnnotation(rect: rect)
                annotations.append(pixelate)
            }

        case .ruler:
            if rect.width > 3 || rect.height > 3 {
                saveUndoState()
                let isHoriz = abs(dragCurrent.x - dragStart.x) > abs(dragCurrent.y - dragStart.y)
                let ruler = RulerAnnotation(start: dragStart, end: dragCurrent, horizontal: isHoriz)
                annotations.append(ruler)
            }

        case .freehand, .highlighter:
            if let freehand = currentFreehand {
                saveUndoState()
                annotations.append(freehand)
                currentFreehand = nil
            }

        case .crop:
            cropRect = rect

        default:
            break
        }

        isDragging = false
        magnifierPosition = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if currentTool == .magnifier || currentTool == .colorPicker {
            magnifierPosition = point
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self
        ))
    }

    // MARK: - Keyboard Events (called from EditorViewController)

    func handleReturnKey() {
        if currentTool == .crop, let _ = cropRect {
            saveUndoState()
            performCrop()
        }
    }

    func handleDeleteKey() {
        if let selected = selectedAnnotation {
            saveUndoState()
            annotations.removeAll { $0.id == selected.id }
            selectedAnnotation = nil
            needsDisplay = true
        }
    }

    func handleKeyDown(with event: NSEvent) {
        // Called from EditorViewController for non-command keys
        keyDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 36: // Return — crop confirm
            handleReturnKey()

        case 51: // Delete
            handleDeleteKey()

        case 49: // Space
            isSpaceHeld = true

        case 48: // Tab
            if currentTool == .colorPicker, let pos = magnifierPosition {
                let color = getPixelColor(at: pos)
                let format = PreferencesManager.shared.colorFormat
                let colorStr = formatColor(color, format: format)
                ClipboardManager.copyText(colorStr)
                NotificationHelper.show(title: "Color Copied", body: colorStr)
            }

        default:
            // Arrow keys for nudging selection
            if let selected = selectedAnnotation {
                let amount: CGFloat = flags.contains(.shift) ? 10 : 1
                switch event.keyCode {
                case 123: moveAnnotation(selected, dx: -amount, dy: 0) // Left
                case 124: moveAnnotation(selected, dx: amount, dy: 0)  // Right
                case 125: moveAnnotation(selected, dx: 0, dy: amount)  // Down (flipped)
                case 126: moveAnnotation(selected, dx: 0, dy: -amount) // Up
                default: super.keyDown(with: event) // Pass unhandled keys up
                }
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Space
            isSpaceHeld = false
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Option+Drag to duplicate
    }

    // MARK: - Undo/Redo

    private func saveUndoState() {
        undoStack.append(annotations.map { $0.copy() })
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations.map { $0.copy() })
        annotations = previous
        needsDisplay = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations.map { $0.copy() })
        annotations = next
        needsDisplay = true
    }

    // MARK: - Tool State Management

    func cancelCurrentOperation() {
        cropRect = nil
        magnifierPosition = nil
        isDragging = false
        currentFreehand = nil
        selectedAnnotation = nil
        needsDisplay = true
    }

    /// Perform the actual crop: replace the image with the cropped region
    func performCrop() {
        guard let rect = cropRect, rect.width > 1, rect.height > 1 else { return }

        // Render current state (image + annotations) then crop from that
        let rendered = renderFinalImage()
        guard let cgImage = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        // renderFinalImage produces bottom-left origin; our crop rect is from flipped (top-left) view
        // Flip Y: CGImage origin is top-left, rendered NSImage is bottom-left
        let flippedY = (image.size.height - rect.origin.y - rect.height)
        let cropCG = CGRect(
            x: rect.origin.x * scaleX,
            y: flippedY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: cropCG) else { return }
        let newSize = NSSize(width: rect.width, height: rect.height)
        let croppedImage = NSImage(cgImage: cropped, size: newSize)

        // Replace the image entirely and clear all annotations (they're baked in)
        image = croppedImage
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()

        // Update frame and clear crop
        cropRect = nil
        frame = NSRect(origin: .zero, size: newSize)
        needsDisplay = true

        // Auto-copy cropped image to clipboard
        ClipboardManager.copyImage(croppedImage)
        NotificationHelper.show(title: "Cropped & Copied", body: "\(Int(newSize.width))×\(Int(newSize.height))")

        // Update dimension label and switch back to select
        editorVC?.updateDimensionLabel(size: newSize)
        editorVC?.switchToSelect()
    }

    // MARK: - OCR Overlay

    var hasOCROverlay: Bool {
        return ocrOverlayBlocks != nil
    }

    func showOCROverlay(blocks: [RecognizedTextBlock]) {
        ocrOverlayBlocks = blocks
        needsDisplay = true
    }

    func dismissOCROverlay() {
        ocrOverlayBlocks = nil
        needsDisplay = true
    }

    func copyAllOCRText() {
        guard let blocks = ocrOverlayBlocks, !blocks.isEmpty else { return }
        let allText = blocks.map { $0.text }.joined(separator: "\n")
        ClipboardManager.copyText(allText)
        NotificationHelper.show(title: "OCR Text Copied", body: "\(blocks.count) blocks copied")
    }

    // MARK: - Render Final Image

    func renderFinalImage() -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        // Draw original image — use NSImage.draw which handles orientation correctly
        // lockFocus context is bottom-left origin (not flipped), so use respectFlipped: false
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0,
                   respectFlipped: false,
                   hints: nil)

        // Apply pixelation annotations
        for annotation in annotations {
            if let pixelate = annotation as? PixelateAnnotation {
                applyPixelation(context: context, pixelate: pixelate, imageSize: size)
            }
        }

        // Draw other annotations
        // lockFocus has bottom-left origin; annotations draw in top-left (flipped) coords
        // so flip the context for annotation drawing
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        for annotation in annotations where !(annotation is PixelateAnnotation) {
            annotation.draw(in: context, imageSize: size)
        }
        context.restoreGState()

        result.unlockFocus()
        return result
    }

    private func applyPixelation(context: CGContext, pixelate: PixelateAnnotation, imageSize: NSSize) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let scaleX = CGFloat(cgImage.width) / imageSize.width
        let scaleY = CGFloat(cgImage.height) / imageSize.height

        // Flip rect for non-flipped context
        let flippedRect = CGRect(
            x: pixelate.rect.origin.x * scaleX,
            y: (imageSize.height - pixelate.rect.origin.y - pixelate.rect.height) * scaleY,
            width: pixelate.rect.width * scaleX,
            height: pixelate.rect.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: flippedRect) else { return }

        let pixelSize = pixelate.pixelSize * scaleX
        let smallWidth = max(1, Int(CGFloat(cropped.width) / pixelSize))
        let smallHeight = max(1, Int(CGFloat(cropped.height) / pixelSize))

        // Downscale
        guard let smallContext = CGContext(
            data: nil, width: smallWidth, height: smallHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        smallContext.interpolationQuality = .none
        smallContext.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))

        guard let smallImage = smallContext.makeImage() else { return }

        // Draw pixelated version back
        let drawRect = CGRect(
            x: pixelate.rect.origin.x,
            y: imageSize.height - pixelate.rect.origin.y - pixelate.rect.height,
            width: pixelate.rect.width,
            height: pixelate.rect.height
        )

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(smallImage, in: drawRect)
        context.restoreGState()
    }

    // MARK: - Color Picking

    func getPixelColor(at point: NSPoint) -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .black
        }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let px = Int(point.x * scaleX)
        let py = Int(point.y * scaleY) // View is flipped

        guard px >= 0, py >= 0, px < cgImage.width, py < cgImage.height else { return .black }

        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return .black }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let offset = py * bytesPerRow + px * bytesPerPixel

        // Assuming BGRA or RGBA format
        let b = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let r = CGFloat(ptr[offset + 2]) / 255.0
        let a = bytesPerPixel > 3 ? CGFloat(ptr[offset + 3]) / 255.0 : 1.0

        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    func formatColor(_ color: NSColor, format: ColorFormat) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent

        switch format {
        case .hexWithHash:
            return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        case .hexWithoutHash:
            return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        case .rgb:
            return String(format: "rgb(%d, %d, %d)", Int(r * 255), Int(g * 255), Int(b * 255))
        case .hsl:
            let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
            return String(format: "hsl(%d, %d%%, %d%%)", Int(h * 360), Int(s * 100), Int(l * 100))
        case .oklch:
            let (l, c, h) = rgbToOKLCH(r: r, g: g, b: b)
            return String(format: "oklch(%.2f %.3f %.1f)", l, c, h)
        }
    }

    private func rgbToHSL(r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2

        guard maxC != minC else { return (0, 0, l) }

        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)

        var h: CGFloat = 0
        if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6

        return (h, s, l)
    }

    private func rgbToOKLCH(r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        // Simplified OKLCH conversion
        let l_ = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m_ = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s_ = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

        let l = cbrt(l_)
        let m = cbrt(m_)
        let s = cbrt(s_)

        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bOk = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        let C = sqrt(a * a + bOk * bOk)
        var H = atan2(bOk, a) * 180.0 / .pi
        if H < 0 { H += 360 }

        return (CGFloat(L), CGFloat(C), CGFloat(H))
    }

    // MARK: - Helpers

    private func moveAnnotation(_ annotation: Annotation, dx: CGFloat, dy: CGFloat) {
        if let arrow = annotation as? ArrowAnnotation {
            arrow.startPoint.x += dx; arrow.startPoint.y += dy
            arrow.endPoint.x += dx; arrow.endPoint.y += dy
        } else if let line = annotation as? LineAnnotation {
            line.startPoint.x += dx; line.startPoint.y += dy
            line.endPoint.x += dx; line.endPoint.y += dy
        } else if let rect = annotation as? RectAnnotation {
            rect.rect.origin.x += dx; rect.rect.origin.y += dy
        } else if let oval = annotation as? OvalAnnotation {
            oval.rect.origin.x += dx; oval.rect.origin.y += dy
        } else if let text = annotation as? TextAnnotation {
            text.position.x += dx; text.position.y += dy
        } else if let freehand = annotation as? FreehandAnnotation {
            freehand.points = freehand.points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
        } else if let spotlight = annotation as? SpotlightAnnotation {
            spotlight.rect.origin.x += dx; spotlight.rect.origin.y += dy
        } else if let counter = annotation as? StepCounterAnnotation {
            counter.position.x += dx; counter.position.y += dy
        } else if let ruler = annotation as? RulerAnnotation {
            ruler.startPoint.x += dx; ruler.startPoint.y += dy
            ruler.endPoint.x += dx; ruler.endPoint.y += dy
        }
    }

    private func promptForText(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Enter text"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "Type annotation text..."
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion(textField.stringValue)
        } else {
            completion(nil)
        }
    }
}
