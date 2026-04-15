import Cocoa

/// Freehand drawing tool with smoothing
struct FreehandToolConfig {
    var smoothing: CGFloat = 0.5 // 0 = no smoothing, 1 = max smoothing

    /// Smooth a series of points using Catmull-Rom interpolation
    static func smooth(points: [NSPoint], factor: CGFloat = 0.5) -> [NSPoint] {
        guard points.count > 2 else { return points }

        var smoothed: [NSPoint] = [points[0]]

        for i in 1..<points.count - 1 {
            let prev = points[i - 1]
            let curr = points[i]
            let next = points[i + 1]

            let smoothX = curr.x + factor * ((prev.x + next.x) / 2 - curr.x)
            let smoothY = curr.y + factor * ((prev.y + next.y) / 2 - curr.y)

            smoothed.append(NSPoint(x: smoothX, y: smoothY))
        }

        smoothed.append(points.last!)
        return smoothed
    }

    /// Reduce points while maintaining shape (Ramer-Douglas-Peucker)
    static func simplify(points: [NSPoint], epsilon: CGFloat = 1.0) -> [NSPoint] {
        guard points.count > 2 else { return points }

        var maxDist: CGFloat = 0
        var maxIdx = 0

        let start = points.first!
        let end = points.last!

        for i in 1..<points.count - 1 {
            let dist = perpendicularDistance(point: points[i], lineStart: start, lineEnd: end)
            if dist > maxDist {
                maxDist = dist
                maxIdx = i
            }
        }

        if maxDist > epsilon {
            let left = simplify(points: Array(points[0...maxIdx]), epsilon: epsilon)
            let right = simplify(points: Array(points[maxIdx...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [start, end]
        }
    }

    private static func perpendicularDistance(point: NSPoint, lineStart: NSPoint, lineEnd: NSPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }

        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / length
    }
}
