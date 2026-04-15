import Cocoa
import Vision

struct DetectedBarcode {
    let payload: String
    let symbology: VNBarcodeSymbology
    let boundingBox: CGRect
}

class QRDetector {
    static let shared = QRDetector()

    func detectBarcodes(in image: NSImage, completion: @escaping (Result<[DetectedBarcode], Error>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNBarcodeObservation] else {
                completion(.success([]))
                return
            }

            let barcodes = observations.compactMap { obs -> DetectedBarcode? in
                guard let payload = obs.payloadStringValue else { return nil }
                let box = CGRect(
                    x: obs.boundingBox.origin.x * CGFloat(cgImage.width),
                    y: (1 - obs.boundingBox.origin.y - obs.boundingBox.height) * CGFloat(cgImage.height),
                    width: obs.boundingBox.width * CGFloat(cgImage.width),
                    height: obs.boundingBox.height * CGFloat(cgImage.height)
                )
                return DetectedBarcode(
                    payload: payload,
                    symbology: obs.symbology,
                    boundingBox: box
                )
            }

            completion(.success(barcodes))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}
