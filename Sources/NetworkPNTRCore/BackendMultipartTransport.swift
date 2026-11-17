import Foundation

@MainActor public protocol BackendMultipartTransport {
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse
}

public extension BackendMultipartTransport {
    func upload(conversationID: Int64, files: [URL], bearer: String) async throws -> BackendHTTPResponse {
        try await upload(conversationID: conversationID, files: files, bearer: bearer, progress: nil)
    }
}

/// Dedicated draft route; UUID ownership belongs to the creation model.
@MainActor public protocol BackendStagingMultipartTransport {
    func uploadStaging(draftID: UUID, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse
}
