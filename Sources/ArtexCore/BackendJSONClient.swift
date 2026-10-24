import Foundation

@MainActor public protocol BackendJSONTransport {
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse
}

@MainActor public final class BackendJSONClient: BackendJSONTransport, BackendMultipartTransport, BackendAttachmentDownloadTransport {
    private let runtime: VMController
    private let provisioning: GuestProvisioning
    public init(runtime: VMController, provisioning: GuestProvisioning) {
        self.runtime = runtime; self.provisioning = provisioning
    }
    public func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard conversationID > 0 else { throw ChatUploadBodyError.invalidFile }
        let preflight = Task.detached { try ChatMultipartPlan(files: files) }
        let plan = try await withTaskCancellationHandler {
            try await preflight.value
        } onCancel: { preflight.cancel() }
        try Task.checkCancellation()
        let header = try BackendMultipartRequest.header(conversationID: conversationID, plan: plan, bearer: bearer)
        return try await runtime.uploadBackend(plan: plan, header: header, provisioning: provisioning, progress: progress)
    }
    public func downloadDigest(_ attachment: ChatAttachmentDownload, bearer: String) async throws -> BackendDownloadResult {
        try Task.checkCancellation()
        let request = try attachment.request(bearer: bearer)
        return try await runtime.downloadBackendDigest(request: request, expectedSize: attachment.expectedSize, provisioning: provisioning)
    }
    public func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let request = try BackendHTTPRequest.make(method: method, path: path, body: body, bearer: bearer)
        let response = try await runtime.probeBackend(request: request, provisioning: provisioning)
        return try BackendHTTPResponse.parse(response)
    }
}

public enum BackendAPIError: LocalizedError {
    case status(Int), invalidResponse, validation(BackendValidation), secureStorage(Int32)
    public var errorDescription: String? { AppErrorText.text(self, language: .japanese) }
}
