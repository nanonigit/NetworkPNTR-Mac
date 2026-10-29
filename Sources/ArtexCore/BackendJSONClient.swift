import Foundation

@MainActor public protocol BackendJSONTransport {
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse
}

@MainActor public final class BackendJSONClient: BackendJSONTransport, BackendMultipartTransport, BackendStagingMultipartTransport, BackendAttachmentDownloadTransport, BackendEvidenceDownloadTransport, BackendTrafficBlobDownloadTransport {
    private let runtime: VMController
    private let provisioning: GuestProvisioning
    public init(runtime: VMController, provisioning: GuestProvisioning) {
        self.runtime = runtime; self.provisioning = provisioning
    }
    public func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard conversationID > 0 else { throw ChatUploadBodyError.invalidFile }
        return try await upload(files: files, progress: progress) { plan in
            try BackendMultipartRequest.header(conversationID: conversationID, plan: plan, bearer: bearer)
        }
    }
    public func uploadStaging(draftID: UUID, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        try await upload(files: files, progress: progress) { plan in
            try BackendMultipartRequest.stagingHeader(draftID: draftID, plan: plan, bearer: bearer)
        }
    }
    private func upload(files: [URL], progress: BackendUploadProgressHandler?, header: (ChatMultipartPlan) throws -> Data) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        let preflight = Task.detached { try ChatMultipartPlan(files: files) }
        let plan = try await withTaskCancellationHandler {
            try await preflight.value
        } onCancel: { preflight.cancel() }
        try Task.checkCancellation()
        return try await runtime.uploadBackend(plan: plan, header: header(plan), provisioning: provisioning, progress: progress)
    }
    public func downloadDigest(_ attachment: ChatAttachmentDownload, bearer: String) async throws -> BackendDownloadResult {
        try Task.checkCancellation()
        let request = try attachment.request(bearer: bearer)
        return try await runtime.downloadBackendDigest(request: request, expectedSize: attachment.expectedSize, provisioning: provisioning)
    }
    public func stageEvidence(_ manifest: FindingEvidenceDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt {
        try Task.checkCancellation()
        return try await runtime.stageBackendEvidence(request: manifest.request(bearer: bearer), manifest: manifest, destination: destination, provisioning: provisioning)
    }
    public func stageTrafficBlob(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt {
        try Task.checkCancellation()
        return try await runtime.stageBackendEvidence(request: manifest.request(bearer: bearer), manifest: manifest, destination: destination, provisioning: provisioning)
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
