import Foundation

@MainActor public protocol BackendMultipartTransport {
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse
}

public extension BackendMultipartTransport {
    func upload(conversationID: Int64, files: [URL], bearer: String) async throws -> BackendHTTPResponse {
        try await upload(conversationID: conversationID, files: files, bearer: bearer, progress: nil)
    }
}
