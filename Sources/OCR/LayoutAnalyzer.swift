import Foundation

private struct PositionedBlock {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let confidence: Float
}

class LayoutAnalyzer {
    /// Reconstruct spatial layout from OCR text blocks, preserving columns and reading order
    static func reconstructLayout(blocks: [RecognizedTextBlock], imageSize: NSSize) -> String {
        guard !blocks.isEmpty else { return "" }

        let positioned = blocks.map { block in
            PositionedBlock(
                text: block.text,
                x: block.boundingBox.origin.x * imageSize.width,
                y: (1 - block.boundingBox.origin.y - block.boundingBox.height) * imageSize.height,
                width: block.boundingBox.width * imageSize.width,
                height: block.boundingBox.height * imageSize.height,
                confidence: block.confidence
            )
        }

        // Sort by Y position (top to bottom), then X (left to right)
        let sorted = positioned.sorted { a, b in
            let yThreshold = max(a.height, b.height) * 0.5
            if abs(a.y - b.y) < yThreshold {
                return a.x < b.x
            }
            return a.y < b.y
        }

        // Group into lines based on Y proximity
        var lines: [[PositionedBlock]] = []
        var currentLine: [PositionedBlock] = []
        var lastY: CGFloat = -1000

        for block in sorted {
            let threshold = block.height * 0.5
            if abs(block.y - lastY) > threshold && !currentLine.isEmpty {
                lines.append(currentLine.sorted { $0.x < $1.x })
                currentLine = []
            }
            currentLine.append(block)
            lastY = block.y
        }
        if !currentLine.isEmpty {
            lines.append(currentLine.sorted { $0.x < $1.x })
        }

        // Detect columns by analyzing X positions
        let columns = detectColumns(lines: lines, imageWidth: imageSize.width)

        if columns > 1 {
            return reconstructMultiColumn(lines: lines, columnCount: columns, imageWidth: imageSize.width)
        }

        // Single column: join with appropriate spacing
        return lines.map { line in
            line.map { $0.text }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    private static func detectColumns(lines: [[PositionedBlock]], imageWidth: CGFloat) -> Int {
        guard lines.count > 3 else { return 1 }

        var xStarts: [CGFloat] = []
        for line in lines {
            for block in line {
                xStarts.append(block.x)
            }
        }

        guard !xStarts.isEmpty else { return 1 }

        xStarts.sort()

        let threshold = imageWidth * 0.1
        var clusters: [[CGFloat]] = [[xStarts[0]]]

        for i in 1..<xStarts.count {
            if xStarts[i] - clusters.last!.last! > threshold {
                clusters.append([xStarts[i]])
            } else {
                clusters[clusters.count - 1].append(xStarts[i])
            }
        }

        let significantClusters = clusters.filter { $0.count >= lines.count / 3 }
        return min(significantClusters.count, 4)
    }

    private static func reconstructMultiColumn(lines: [[PositionedBlock]], columnCount: Int, imageWidth: CGFloat) -> String {
        let colWidth = imageWidth / CGFloat(columnCount)

        var columnTexts: [[String]] = Array(repeating: [], count: columnCount)

        for line in lines {
            var lineByColumn: [Int: [String]] = [:]
            for block in line {
                let col = min(Int(block.x / colWidth), columnCount - 1)
                lineByColumn[col, default: []].append(block.text)
            }
            for (col, texts) in lineByColumn.sorted(by: { $0.key < $1.key }) {
                columnTexts[col].append(texts.joined(separator: " "))
            }
        }

        return columnTexts.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
