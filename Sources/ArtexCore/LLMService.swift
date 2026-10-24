import Foundation

/// Feature clients cannot inject a separate bearer or bypass the live auth session.
@MainActor public final class AuthenticatedBackendClient: BackendJSONTransport, ChatAttachmentUploading {
    private let session: AuthenticationSession
    public init(session: AuthenticationSession) { self.session = session }
    public func uploadAttachments(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [ChatAttachment] {
        let response = try await session.authenticatedUpload(conversationID: conversationID, files: files, progress: progress)
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        let attachments = try BackendJSONCoding.decode(ChatUploadResponse.self, from: response.body).attachments
        guard attachments.count == files.count else { throw BackendAPIError.invalidResponse }
        return attachments
    }
    public func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        guard bearer == nil else { throw BackendAPIError.invalidResponse }
        return try await session.authenticatedRequest(method: method, path: path, body: body)
    }
}

public struct LLMConnectionResult: Decodable, Sendable {
    public let ok: Bool
    public let reply: String?
    public let model: String?
    public let latencyMs: Double?
}

@MainActor public final class LLMService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    private struct Profiles: Decodable { let profiles: [LLMProfile] }
    private struct Saved: Decodable { let id: Int64 }
    private struct IDRequest: Encodable { let id: Int64 }
    private struct Acknowledgement: Decodable { let ok: Bool }
    private struct Deleted: Decodable { let deleted: Int64 }
    private struct Models: Decodable { let ok: Bool; let models: [String]? }
    private struct Probe: Encodable {
        let provider: LLMFormat
        let baseUrl: String
        let proxy: String
        let apiKey: String
        let profileId: Int64?
        var model: String?
        var thinkingType: String?
        var reasoningEffort: String?
        var streaming: Bool?
        var sessionHeaderKey: String?
        init(_ draft: LLMProfileDraft) throws {
            if let id = draft.id, id <= 0 { throw BackendAPIError.invalidResponse }
            provider = draft.format; baseUrl = draft.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            proxy = draft.proxy.trimmingCharacters(in: .whitespacesAndNewlines)
            apiKey = draft.apiKey; profileId = draft.id
        }
    }
    private func raw(method: String, path: String, body: Data? = nil) async throws -> Data {
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        return response.body
    }
    private func request<T: Decodable>(_ type: T.Type, method: String = "GET", path: String, body: Data? = nil) async throws -> T {
        try LLMWire.decode(type, from: await raw(method: method, path: path, body: body))
    }
    public func profiles() async throws -> [LLMProfile] {
        try await request(Profiles.self, path: "/api/llm/profiles").profiles
    }
    public func save(_ draft: LLMProfileDraft) async throws -> Int64 {
        let saved = try await request(Saved.self, method: "POST", path: "/api/llm/profiles", body: draft.encoded())
        guard saved.id > 0 else { throw BackendAPIError.invalidResponse }
        return saved.id
    }
    public func activate(id: String) async throws {
        let body = try LLMWire.encode(IDRequest(id: LLMWire.numericID(id)))
        let result = try await request(Acknowledgement.self, method: "POST", path: "/api/llm/profiles/active", body: body)
        guard result.ok else { throw BackendAPIError.invalidResponse }
    }
    public func delete(id: String, isActive: Bool) async throws {
        guard !isActive else { throw BackendAPIError.validation("有効なモデル設定は削除できません。先に別の設定を有効にしてください。") }
        let identifier = try LLMWire.numericID(id)
        let result = try await request(Deleted.self, method: "DELETE", path: "/api/llm/profiles/\(identifier)")
        guard result.deleted == identifier else { throw BackendAPIError.invalidResponse }
    }
    public func pool() async throws -> LLMPoolStatus {
        try await request(LLMPoolStatus.self, path: "/api/llm/pool")
    }
    public func resetPool(id: String? = nil) async throws -> LLMPoolStatus {
        let identifier = try id.map(LLMWire.numericID) ?? 0
        return try await request(LLMPoolStatus.self, method: "POST", path: "/api/llm/pool/reset", body: LLMWire.encode(IDRequest(id: identifier)))
    }
    public func setRotation(enabled: Bool?, bindFallback: Bool?) async throws {
        var patch: [String: Bool] = [:]
        if let enabled { patch["llm_pool_enabled"] = enabled }
        if let bindFallback { patch["llm_pool_bind_fallback"] = bindFallback }
        guard !patch.isEmpty else { return }
        let data = try await raw(method: "PUT", path: "/api/settings", body: LLMWire.encode(patch))
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              patch.allSatisfy({ settings[$0.key] as? Bool == $0.value }) else { throw BackendAPIError.invalidResponse }
    }
    public func retry() async throws -> LLMRetryPolicy {
        try await request(LLMRetryPolicy.self, path: "/api/llm/retry-policy")
    }
    public func saveRetry(_ policy: LLMRetryPolicy) async throws -> LLMRetryPolicy {
        try await request(LLMRetryPolicy.self, method: "POST", path: "/api/llm/retry-policy", body: LLMWire.encode(policy.clamped()))
    }
    public func models(_ draft: LLMProfileDraft) async throws -> [String] {
        let result = try await request(Models.self, method: "POST", path: "/api/llm/models", body: LLMWire.encode(Probe(draft)))
        guard result.ok, let models = result.models, !models.isEmpty else { throw BackendAPIError.validation("モデル一覧を取得できませんでした。キー・URL・外向き通信の設定を確認してください。") }
        return models
    }
    public func test(_ draft: LLMProfileDraft) async throws -> LLMConnectionResult {
        var probe = try Probe(draft)
        probe.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard probe.model?.isEmpty == false else { throw BackendAPIError.validation("テストするモデルを入力してください。") }
        probe.thinkingType = draft.thinkingType; probe.reasoningEffort = draft.reasoningEffort
        probe.streaming = draft.streaming
        probe.sessionHeaderKey = try draft.validatedSessionHeader()
        let result = try await request(LLMConnectionResult.self, method: "POST", path: "/api/llm/test", body: LLMWire.encode(probe))
        guard result.ok else { throw BackendAPIError.validation("接続テストに失敗しました。モデル・キー・URL・外向き通信の設定を確認してください。") }
        return result
    }
}
