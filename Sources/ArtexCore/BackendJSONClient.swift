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
    public func upload(conversationID: Int64, files: [URL], bearer: String) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard conversationID > 0 else { throw ChatUploadBodyError.invalidFile }
        let preflight = Task.detached { try ChatMultipartPlan(files: files) }
        let plan = try await withTaskCancellationHandler {
            try await preflight.value
        } onCancel: { preflight.cancel() }
        try Task.checkCancellation()
        let header = try BackendMultipartRequest.header(conversationID: conversationID, plan: plan, bearer: bearer)
        return try await runtime.uploadBackend(plan: plan, header: header, provisioning: provisioning)
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
    case status(Int), invalidResponse, validation(String), secureStorage(Int32)
    public var errorDescription: String? {
        switch self {
        case .status(401): return "ユーザー名またはパスワードが正しくありません。"
        case .status(403): return "この操作は許可されていません。初期設定の状態を確認してください。"
        case .status(429): return "試行回数が多いため、しばらく待ってから再試行してください。"
        case .status(503): return "データベースを利用できません。復旧後に再試行してください。"
        case let .status(code): return "実行環境との通信に失敗しました（HTTP \(code)）。"
        case .invalidResponse: return "実行環境からの応答を確認できませんでした。"
        case let .validation(message): return message
        case let .secureStorage(code): return "Keychainの操作に失敗しました（\(code)）。"
        }
    }
}
