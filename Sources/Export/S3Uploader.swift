import Foundation
import CommonCrypto

class S3Uploader {
    struct Config {
        let endpoint: String
        let bucket: String
        let accessKey: String
        let secretKey: String
        let region: String
    }

    static func upload(imageData: Data, filename: String, config: Config,
                       completion: @escaping (Result<String, Error>) -> Void) {
        guard !config.endpoint.isEmpty, !config.bucket.isEmpty,
              !config.accessKey.isEmpty, !config.secretKey.isEmpty else {
            completion(.failure(S3Error.missingConfig))
            return
        }

        let contentType = filename.hasSuffix(".png") ? "image/png" : "image/jpeg"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: Date())

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: Date())

        // Build canonical request
        let host: String
        let path: String
        if config.endpoint.contains(config.bucket) {
            host = config.endpoint.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            path = "/\(filename)"
        } else {
            host = config.endpoint.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            path = "/\(config.bucket)/\(filename)"
        }

        let payloadHash = sha256Hex(imageData)
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = "PUT\n\(path)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"

        let credentialScope = "\(dateStamp)/\(config.region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(sha256Hex(canonicalRequest.data(using: .utf8)!))"

        // Derive signing key
        let kDate = hmacSHA256(key: "AWS4\(config.secretKey)".data(using: .utf8)!, data: dateStamp.data(using: .utf8)!)
        let kRegion = hmacSHA256(key: kDate, data: config.region.data(using: .utf8)!)
        let kService = hmacSHA256(key: kRegion, data: "s3".data(using: .utf8)!)
        let kSigning = hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8)!)

        let signature = hmacSHA256(key: kSigning, data: stringToSign.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        // Build request
        let scheme = config.endpoint.hasPrefix("https") ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host)\(path)") else {
            completion(.failure(S3Error.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = imageData
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(S3Error.uploadFailed))
                return
            }

            let publicURL = "\(scheme)://\(host)\(path)"
            completion(.success(publicURL))
        }.resume()
    }

    private static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr.baseAddress, key.count, dataPtr.baseAddress, data.count, &hash)
            }
        }
        return Data(hash)
    }

    enum S3Error: LocalizedError {
        case missingConfig
        case invalidURL
        case uploadFailed

        var errorDescription: String? {
            switch self {
            case .missingConfig: return "S3 configuration is incomplete."
            case .invalidURL: return "Invalid S3 endpoint URL."
            case .uploadFailed: return "Upload to S3 failed."
            }
        }
    }
}
