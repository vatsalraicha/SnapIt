import Cocoa
import Vision

struct RecognizedTextBlock {
    let text: String
    let boundingBox: CGRect // Normalized (0...1) coordinates
    let confidence: Float
}

class TextRecognizer {
    static let shared = TextRecognizer()

    func recognizeText(in image: NSImage, level: VNRequestTextRecognitionLevel = .accurate,
                       completion: @escaping (Result<String, Error>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success(""))
                return
            }

            let blocks = observations.compactMap { obs -> RecognizedTextBlock? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return RecognizedTextBlock(
                    text: candidate.string,
                    boundingBox: obs.boundingBox,
                    confidence: candidate.confidence
                )
            }

            let text = LayoutAnalyzer.reconstructLayout(blocks: blocks, imageSize: image.size)
            let cleaned = self.cleanText(text)
            completion(.success(cleaned))
        }

        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = PreferencesManager.shared.ocrLanguages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    func recognizeTextBlocks(in image: NSImage,
                             completion: @escaping (Result<[RecognizedTextBlock], Error>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success([]))
                return
            }

            let blocks = observations.compactMap { obs -> RecognizedTextBlock? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return RecognizedTextBlock(
                    text: candidate.string,
                    boundingBox: obs.boundingBox,
                    confidence: candidate.confidence
                )
            }

            completion(.success(blocks))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = PreferencesManager.shared.ocrLanguages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    func getTextBoundingBoxes(in image: NSImage,
                              completion: @escaping (Result<[CGRect], Error>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success([]))
                return
            }

            let boxes = observations.map { obs in
                // Convert from Vision normalized coordinates to image coordinates
                CGRect(
                    x: obs.boundingBox.origin.x * CGFloat(cgImage.width),
                    y: (1 - obs.boundingBox.origin.y - obs.boundingBox.height) * CGFloat(cgImage.height),
                    width: obs.boundingBox.width * CGFloat(cgImage.width),
                    height: obs.boundingBox.height * CGFloat(cgImage.height)
                )
            }

            completion(.success(boxes))
        }

        request.recognitionLevel = .fast
        request.recognitionLanguages = PreferencesManager.shared.ocrLanguages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func cleanText(_ text: String) -> String {
        var cleaned = text
        // Fix double spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        if PreferencesManager.shared.stripLineBreaks {
            cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image for OCR."
        case .recognitionFailed: return "Text recognition failed."
        }
    }
}
