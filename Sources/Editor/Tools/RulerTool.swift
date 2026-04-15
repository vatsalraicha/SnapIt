import Cocoa

/// Ruler/measurement tool for measuring distances
struct RulerToolConfig {
    var showGuides: Bool = true
    var snapToPixel: Bool = true

    func createAnnotation(from start: NSPoint, to end: NSPoint) -> RulerAnnotation {
        let isHorizontal = abs(end.x - start.x) > abs(end.y - start.y)

        var adjustedEnd = end
        if isHorizontal {
            adjustedEnd.y = start.y // Snap to horizontal
        } else {
            adjustedEnd.x = start.x // Snap to vertical
        }

        if snapToPixel {
            adjustedEnd.x = round(adjustedEnd.x)
            adjustedEnd.y = round(adjustedEnd.y)
        }

        return RulerAnnotation(start: start, end: adjustedEnd, horizontal: isHorizontal)
    }

    /// Measure distance between two color boundaries
    static func measureGap(in image: NSImage, from point: NSPoint, direction: Direction) -> CGFloat? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        let startX = Int(point.x * scaleX)
        let startY = Int(point.y * scaleY)

        guard startX >= 0, startY >= 0, startX < cgImage.width, startY < cgImage.height else { return nil }

        // Get starting color
        let startOffset = startY * bytesPerRow + startX * bytesPerPixel
        let startR = ptr[startOffset + 2]
        let startG = ptr[startOffset + 1]
        let startB = ptr[startOffset]

        let threshold: UInt8 = 30
        var distance: CGFloat = 0

        let (dx, dy) = direction.delta
        var x = startX
        var y = startY

        while x >= 0 && x < cgImage.width && y >= 0 && y < cgImage.height {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let r = ptr[offset + 2]
            let g = ptr[offset + 1]
            let b = ptr[offset]

            let diff = max(
                abs(Int(r) - Int(startR)),
                abs(Int(g) - Int(startG)),
                abs(Int(b) - Int(startB))
            )

            if diff > Int(threshold) {
                return distance / (direction == .left || direction == .right ? scaleX : scaleY)
            }

            x += dx
            y += dy
            distance += 1
        }

        return nil
    }

    enum Direction {
        case up, down, left, right

        var delta: (Int, Int) {
            switch self {
            case .up: return (0, -1)
            case .down: return (0, 1)
            case .left: return (-1, 0)
            case .right: return (1, 0)
            }
        }
    }
}
