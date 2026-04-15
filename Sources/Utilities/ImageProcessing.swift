import Cocoa
import CoreImage

class ImageProcessing {
    /// Resize image to a given size
    static func resize(_ image: NSImage, to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Resize by percentage
    static func resize(_ image: NSImage, percentage: CGFloat) -> NSImage {
        let newSize = NSSize(
            width: image.size.width * percentage / 100,
            height: image.size.height * percentage / 100
        )
        return resize(image, to: newSize)
    }

    /// Crop image to rect
    static func crop(_ image: NSImage, to rect: NSRect) -> NSImage {
        let result = NSImage(size: rect.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: rect.size),
                   from: rect,
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Add rounded corners
    static func roundCorners(_ image: NSImage, radius: CGFloat) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: radius, yRadius: radius)
        path.addClip()
        image.draw(in: NSRect(origin: .zero, size: size))

        result.unlockFocus()
        return result
    }

    /// Add shadow to image
    static func addShadow(_ image: NSImage, color: NSColor = .black,
                          offset: NSSize = NSSize(width: 0, height: -4),
                          blur: CGFloat = 12) -> NSImage {
        let padding = blur * 2 + max(abs(offset.width), abs(offset.height))
        let newSize = NSSize(
            width: image.size.width + padding * 2,
            height: image.size.height + padding * 2
        )

        let result = NSImage(size: newSize)
        result.lockFocus()

        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.4)
        shadow.shadowOffset = offset
        shadow.shadowBlurRadius = blur
        shadow.set()

        let drawRect = NSRect(x: padding, y: padding,
                             width: image.size.width, height: image.size.height)
        image.draw(in: drawRect)

        result.unlockFocus()
        return result
    }

    /// Add gradient background behind image
    static func addGradientBackground(to image: NSImage, colors: [NSColor],
                                       padding: CGFloat = 40,
                                       cornerRadius: CGFloat = 12,
                                       shadowBlur: CGFloat = 20) -> NSImage {
        // Round corners first
        let rounded = roundCorners(image, radius: cornerRadius)

        // Calculate total size with padding
        let totalSize = NSSize(
            width: rounded.size.width + padding * 2 + shadowBlur * 2,
            height: rounded.size.height + padding * 2 + shadowBlur * 2
        )

        let result = NSImage(size: totalSize)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        // Draw gradient background
        let gradientColors = colors.map { $0.cgColor } as CFArray
        let locations: [CGFloat] = colors.enumerated().map { CGFloat($0.offset) / CGFloat(max(1, colors.count - 1)) }

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors,
                                      locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: totalSize.width, y: totalSize.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Draw shadow + image
        let imageRect = NSRect(
            x: padding + shadowBlur,
            y: padding + shadowBlur,
            width: rounded.size.width,
            height: rounded.size.height
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = shadowBlur
        shadow.set()

        rounded.draw(in: imageRect)

        result.unlockFocus()
        return result
    }

    /// Content-aware erase (simplified: fills with average surrounding color)
    static func contentAwareErase(_ image: NSImage, rect: NSRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        let result = NSImage(size: image.size)
        result.lockFocus()

        // Draw original
        image.draw(in: NSRect(origin: .zero, size: image.size))

        // Sample border pixels to get average color
        let sampleWidth: CGFloat = 5
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var sampleCount: CGFloat = 0

        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        // Sample top and bottom edges
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2) {
            for yOffset in [-sampleWidth, rect.height + sampleWidth] {
                let y = rect.origin.y + yOffset
                let px = max(0, min(CGFloat(bitmap.pixelsWide - 1), CGFloat(x)))
                let py = max(0, min(CGFloat(bitmap.pixelsHigh - 1), CGFloat(y)))
                if let color = bitmap.colorAt(x: Int(px), y: Int(py))?.usingColorSpace(.sRGB) {
                    totalR += color.redComponent
                    totalG += color.greenComponent
                    totalB += color.blueComponent
                    sampleCount += 1
                }
            }
        }

        // Sample left and right edges
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2) {
            for xOffset in [-sampleWidth, rect.width + sampleWidth] {
                let x = rect.origin.x + xOffset
                let px = max(0, min(CGFloat(bitmap.pixelsWide - 1), CGFloat(x)))
                let py = max(0, min(CGFloat(bitmap.pixelsHigh - 1), CGFloat(y)))
                if let color = bitmap.colorAt(x: Int(px), y: Int(py))?.usingColorSpace(.sRGB) {
                    totalR += color.redComponent
                    totalG += color.greenComponent
                    totalB += color.blueComponent
                    sampleCount += 1
                }
            }
        }

        if sampleCount > 0 {
            let avgColor = NSColor(
                red: totalR / sampleCount,
                green: totalG / sampleCount,
                blue: totalB / sampleCount,
                alpha: 1.0
            )
            avgColor.setFill()
            // Fill in non-flipped coordinates
            let fillRect = NSRect(
                x: rect.origin.x,
                y: image.size.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            fillRect.fill()
        }

        result.unlockFocus()
        return result
    }

    /// Create animated GIF from frames
    static func createAnimatedGIF(frames: [NSImage], frameDelay: Double = 0.5) -> Data? {
        guard !frames.isEmpty else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else { return nil }

        let gifProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0 // Loop forever
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, gifProperties)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ] as CFDictionary

        for frame in frames {
            if let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                CGImageDestinationAddImage(destination, cgImage, frameProperties)
            }
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Average color of a region
    static func averageColor(of image: NSImage, in rect: NSRect) -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .black }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let scaledRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: scaledRect) else { return .black }

        let ciImage = CIImage(cgImage: cropped)
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(x: extent.origin.x, y: extent.origin.y,
                                        z: extent.width, w: extent.height)
        ])

        guard let outputImage = filter?.outputImage else { return .black }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1.0
        )
    }

    /// WCAG 2.0 contrast ratio between two colors
    static func contrastRatio(_ color1: NSColor, _ color2: NSColor) -> Double {
        let l1 = relativeLuminance(color1)
        let l2 = relativeLuminance(color2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// APCA contrast
    static func apcaContrast(_ textColor: NSColor, _ bgColor: NSColor) -> Double {
        guard let tc = textColor.usingColorSpace(.sRGB),
              let bc = bgColor.usingColorSpace(.sRGB) else { return 0 }

        let tY = 0.2126729 * pow(tc.redComponent, 2.4) +
                 0.7151522 * pow(tc.greenComponent, 2.4) +
                 0.0721750 * pow(tc.blueComponent, 2.4)
        let bY = 0.2126729 * pow(bc.redComponent, 2.4) +
                 0.7151522 * pow(bc.greenComponent, 2.4) +
                 0.0721750 * pow(bc.blueComponent, 2.4)

        // Simplified APCA Lc
        if bY > tY {
            return (pow(bY, 0.56) - pow(tY, 0.57)) * 1.14
        } else {
            return (pow(bY, 0.65) - pow(tY, 0.62)) * 1.14
        }
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        let r = linearize(rgb.redComponent)
        let g = linearize(rgb.greenComponent)
        let b = linearize(rgb.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func linearize(_ c: CGFloat) -> Double {
        let v = Double(c)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
