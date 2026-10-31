import Foundation

/// OkHttp-compatible multipart data. Binary image bytes are never converted to text.
public struct MultipartBody: Sendable {
    public struct Part: Sendable {
        public var name: String
        public var filename: String?
        public var contentType: String
        public var data: Data

        public init(name: String, value: String) {
            self.name = name
            self.filename = nil
            self.contentType = "text/plain; charset=utf-8"
            self.data = Data(value.utf8)
        }

        public init(name: String, filename: String, contentType: String, data: Data) {
            self.name = name
            self.filename = filename
            self.contentType = contentType
            self.data = data
        }
    }

    public let boundary: String
    public var parts: [Part]

    public init(parts: [Part], boundary: String = "Anixart-" + UUID().uuidString) {
        // Only token characters can enter the Content-Type header.
        let safe = boundary.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        self.boundary = safe.isEmpty ? "Anixart-" + UUID().uuidString : safe
        self.parts = parts
    }

    public func encoded() -> Data {
        var result = Data()
        func append(_ string: String) { result.append(contentsOf: string.utf8) }
        for part in parts {
            append("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(quoted(part.name))\""
            if let filename = part.filename { disposition += "; filename=\"\(quoted(filename))\"" }
            append(disposition + "\r\n")
            let type = part.contentType.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            append("Content-Type: \(type)\r\n\r\n")
            result.append(part.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return result
    }

    private func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\\", with: "%5C")
    }
}
