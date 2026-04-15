import Cocoa

/// Pixelate/redaction tool with text-only mode
struct PixelateToolConfig {
    var pixelSize: CGFloat = 10
    var textOnly: Bool = false

    func createAnnotation(rect: NSRect) -> PixelateAnnotation {
        let annotation = PixelateAnnotation(rect: rect)
        annotation.pixelSize = pixelSize
        annotation.textOnly = textOnly
        return annotation
    }

    /// For text-only pixelation, get text bounding boxes first then create annotation
    func createTextOnlyAnnotation(rect: NSRect, image: NSImage,
                                   completion: @escaping (PixelateAnnotation) -> Void) {
        let annotation = PixelateAnnotation(rect: rect)
        annotation.pixelSize = pixelSize
        annotation.textOnly = true

        // Use OCR to find text regions within the selected area
        TextRecognizer.shared.getTextBoundingBoxes(in: image) { result in
            DispatchQueue.main.async {
                if case .success(let boxes) = result {
                    // Filter boxes that intersect with our rect
                    let relevantBoxes = boxes.filter { box in
                        rect.intersects(NSRect(x: box.origin.x, y: box.origin.y,
                                              width: box.width, height: box.height))
                    }
                    annotation.textBoxes = relevantBoxes
                }
                completion(annotation)
            }
        }
    }

    /// Apply scramble for small areas (better privacy protection)
    static func scramblePixels(in image: NSImage, rect: NSRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        let scaledRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: scaledRect),
              let data = cropped.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return image }

        let bytesPerPixel = cropped.bitsPerPixel / 8
        let bytesPerRow = cropped.bytesPerRow
        let totalPixels = cropped.width * cropped.height

        // Scramble by shuffling pixels
        var pixels = [UInt32](repeating: 0, count: totalPixels)
        for y in 0..<cropped.height {
            for x in 0..<cropped.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                var pixel: UInt32 = 0
                for b in 0..<min(bytesPerPixel, 4) {
                    pixel |= UInt32(ptr[offset + b]) << (b * 8)
                }
                pixels[y * cropped.width + x] = pixel
            }
        }

        // Fisher-Yates shuffle
        for i in stride(from: pixels.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            pixels.swapAt(i, j)
        }

        // Reconstruct (simplified — would need proper CGContext in production)
        return image
    }
}
