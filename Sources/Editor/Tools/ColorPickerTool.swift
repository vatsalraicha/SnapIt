import Cocoa

/// Color picker tool with multiple format support
struct ColorPickerToolConfig {
    /// Get the darkest pixel in a 20x20 area (for sampling text color)
    static func darkestColor(in image: NSImage, around point: NSPoint, areaSize: CGFloat = 20) -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return .black }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        let halfSize = Int(areaSize * scaleX / 2)
        let centerX = Int(point.x * scaleX)
        let centerY = Int(point.y * scaleY)

        var darkestLuminance: CGFloat = 1.0
        var darkestColor = NSColor.black

        for dy in -halfSize...halfSize {
            for dx in -halfSize...halfSize {
                let x = centerX + dx
                let y = centerY + dy
                guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { continue }

                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = CGFloat(ptr[offset + 2]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset]) / 255.0

                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                if luminance < darkestLuminance {
                    darkestLuminance = luminance
                    darkestColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                }
            }
        }

        return darkestColor
    }

    /// WCAG contrast ratio check and formatted result
    static func contrastCheck(color1: NSColor, color2: NSColor, useAPCA: Bool = false) -> String {
        if useAPCA {
            let contrast = ImageProcessing.apcaContrast(color1, color2)
            return String(format: "APCA Lc: %.1f", contrast * 100)
        } else {
            let ratio = ImageProcessing.contrastRatio(color1, color2)
            let level: String
            if ratio >= 7.0 {
                level = "AAA"
            } else if ratio >= 4.5 {
                level = "AA"
            } else if ratio >= 3.0 {
                level = "AA Large"
            } else {
                level = "Fail"
            }
            return String(format: "%.2f:1 (%@)", ratio, level)
        }
    }
}
