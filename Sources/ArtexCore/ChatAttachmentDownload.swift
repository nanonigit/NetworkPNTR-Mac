import Foundation

/// A single guest attachment, never an arbitrary URL or host file path.
public struct ChatAttachmentDownload: Sendable {
    public let conversationID: Int64
    public let name: String
    public let expectedSize: Int64
    public init(conversationID: Int64, name: String, expectedSize: Int64) throws {
        guard conversationID > 0, !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == "/" || $0 == "\\" }),
              (0...BackendDownloadDigest.maximumBytes).contains(expectedSize) else { throw BackendAPIError.invalidResponse }
        self.conversationID = conversationID; self.name = name; self.expectedSize = expectedSize
    }
    func request(bearer: String) throws -> Data {
        guard !bearer.isEmpty, bearer.utf8.count <= 8192,
              bearer.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95,126].contains($0) }) else { throw BackendAPIError.invalidResponse }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "path", value: "sessions/conv-\(conversationID)/uploads/" + name)]
        guard let encoded = query.percentEncodedQuery else { throw BackendAPIError.invalidResponse }
        return Data(("GET /api/workspace/download?" + encoded + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nAccept: application/octet-stream\r\nAccept-Encoding: identity\r\nContent-Length: 0\r\nAuthorization: Bearer \(bearer)\r\n\r\n").utf8)
    }
}

@MainActor public protocol BackendAttachmentDownloadTransport {
    func downloadDigest(_ attachment: ChatAttachmentDownload, bearer: String) async throws -> BackendDownloadResult
}
