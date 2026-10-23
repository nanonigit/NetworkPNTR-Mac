import Foundation

@MainActor public protocol BackendMultipartTransport {
    func upload(conversationID: Int64, files: [URL], bearer: String) async throws -> BackendHTTPResponse
}
