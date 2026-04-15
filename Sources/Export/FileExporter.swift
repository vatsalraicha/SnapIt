import Cocoa
import UniformTypeIdentifiers

class FileExporter {
    static func save(image: NSImage, windowTitle: String? = nil, completion: ((URL?) -> Void)? = nil) {
        let prefs = PreferencesManager.shared

        if prefs.autoSave {
            let url = autoSaveURL(windowTitle: windowTitle)
            let format = detectBestFormat(for: image)
            if writeImage(image, to: url, format: format) {
                completion?(url)
            } else {
                completion?(nil)
            }
            return
        }

        // Show save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = generateFilename(windowTitle: windowTitle)
        panel.directoryURL = URL(fileURLWithPath: prefs.defaultSaveFolder)

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion?(nil)
                return
            }

            let format = self.formatFromExtension(url.pathExtension)
            if self.writeImage(image, to: url, format: format) {
                completion?(url)
            } else {
                completion?(nil)
            }
        }
    }

    static func autoSaveURL(windowTitle: String? = nil) -> URL {
        let folder = PreferencesManager.shared.defaultSaveFolder
        let filename = generateFilename(windowTitle: windowTitle)
        let folderURL = URL(fileURLWithPath: folder)

        // Ensure folder exists
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        return folderURL.appendingPathComponent(filename)
    }

    /// Save image directly to a URL without showing a panel. Used by auto-save.
    @discardableResult
    static func saveDirectly(image: NSImage, to url: URL) -> Bool {
        let format = detectBestFormat(for: image)
        return writeImage(image, to: url, format: format)
    }

    private static func generateFilename(windowTitle: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let timestamp = formatter.string(from: Date())

        if let title = windowTitle, !title.isEmpty {
            // Sanitize: remove characters invalid in filenames, trim length
            let sanitized = title
                .replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "-", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(60)
            return "SnapIt_\(sanitized)_\(timestamp).png"
        }
        return "SnapIt_\(timestamp).png"
    }

    private static func detectBestFormat(for image: NSImage) -> ImageFormat {
        // Heuristic: if image has lots of text/UI, use PNG; if photo-like, use JPEG
        // Simple approach: check color variance
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return .png
        }

        let totalBytes = CFDataGetLength(data)
        let sampleCount = min(1000, totalBytes / 4)
        var colorVariance: Double = 0

        for i in stride(from: 0, to: sampleCount * 4, by: 4) {
            let r = Double(ptr[i])
            let g = Double(ptr[i + 1])
            let b = Double(ptr[i + 2])
            let avg = (r + g + b) / 3
            colorVariance += abs(r - avg) + abs(g - avg) + abs(b - avg)
        }
        colorVariance /= Double(sampleCount)

        return colorVariance > 30 ? .jpeg : .png
    }

    private static func formatFromExtension(_ ext: String) -> ImageFormat {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "tiff", "tif": return .tiff
        default: return .png
        }
    }

    @discardableResult
    private static func writeImage(_ image: NSImage, to url: URL, format: ImageFormat) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)

        let data: Data?
        switch format {
        case .png:
            data = rep.representation(using: .png, properties: [:])
        case .jpeg:
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .tiff:
            data = rep.representation(using: .tiff, properties: [:])
        }

        guard let imageData = data else { return false }

        do {
            try imageData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    enum ImageFormat {
        case png, jpeg, tiff
    }
}
