import Foundation

public struct ChatPage: Decodable, Equatable, Sendable {
    public let items: [ChatActivity]
    public let cursor: Int64
    public let running: Bool
    public let hasMore: Bool
    private enum CodingKeys: CodingKey { case items, cursor, running, hasMore }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.items) else { throw BackendAPIError.invalidResponse }
        items = try values.decodeIfPresent([ChatActivity].self, forKey: .items) ?? []
        cursor = try values.decodeIfPresent(Int64.self, forKey: .cursor) ?? 0
        running = try values.decodeIfPresent(Bool.self, forKey: .running) ?? false
        hasMore = try values.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        guard cursor >= 0, items.allSatisfy({ $0.seq > 0 }) else { throw BackendAPIError.invalidResponse }
    }
}
public struct ChatDeleteResult: Decodable, Equatable, Sendable {
    public let id: Int64
    public let ok: Bool
}
public enum ChatStopStatus: String, Decodable, Sendable { case idle, stopping }

@MainActor public final class ChatService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    private struct List: Decodable {
        let conversations: [ChatConversation]
        private enum CodingKeys: CodingKey { case conversations }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard values.contains(.conversations) else { throw BackendAPIError.invalidResponse }
            conversations = try values.decodeIfPresent([ChatConversation].self, forKey: .conversations) ?? []
        }
    }
    private struct Acknowledgement: Decodable { let ok: Bool }
    private struct Deleted: Decodable { let deleted: Int64 }
    private struct Batch: Decodable { let items: [ChatDeleteResult] }
    private struct Detail: Decodable { let detail: String? }
    private struct Status: Decodable { let status: String }
    private struct Stop: Decodable { let status: ChatStopStatus }

    private func request<T: Decodable>(_ type: T.Type, method: String = "GET", path: String, body: [String: Any]? = nil) async throws -> T {
        let bytes = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        let response = try await client.send(method: method, path: path, body: bytes, bearer: nil)
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(type, from: response.body)
    }
    private func route(_ id: Int64) throws -> String {
        guard id > 0 else { throw BackendAPIError.invalidResponse }
        return "/api/conversations/\(id)"
    }
    private func profileValue(_ id: Int64?) throws -> Any {
        guard id == nil || id! > 0 else { throw BackendAPIError.invalidResponse }
        return id.map { $0 as Any } ?? NSNull()
    }
    private func validateText(_ value: String, maximum: Int, allowEmpty: Bool = false) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (allowEmpty || !trimmed.isEmpty), trimmed.unicodeScalars.count <= maximum else {
            throw BackendAPIError.validation("会話の入力内容を確認してください。")
        }
    }
    private func validate(_ conversation: ChatConversation, expectedID: Int64? = nil) throws -> ChatConversation {
        guard conversation.id > 0, expectedID == nil || conversation.id == expectedID else { throw BackendAPIError.invalidResponse }
        return conversation
    }
    public func conversations() async throws -> [ChatConversation] {
        let items = try await request(List.self, path: "/api/conversations").conversations
        guard items.allSatisfy({ $0.id > 0 }), Set(items.map(\.id)).count == items.count else { throw BackendAPIError.invalidResponse }
        return items
    }
    public func create(agentKey: String, title: String = "", profileID: Int64? = nil) async throws -> ChatConversation {
        try validateText(agentKey, maximum: 120); try validateText(title, maximum: 200, allowEmpty: true)
        let body: [String: Any] = ["agent_key": agentKey, "title": title, "llm_profile_id": try profileValue(profileID)]
        return try validate(await request(ChatConversation.self, method: "POST", path: "/api/conversations", body: body))
    }
    public func rename(id: Int64, title: String) async throws -> ChatConversation {
        try validateText(title, maximum: 200)
        return try validate(await request(ChatConversation.self, method: "PATCH", path: route(id), body: ["title": title]), expectedID: id)
    }
    public func pin(id: Int64, pinned: Bool) async throws -> ChatConversation {
        try validate(await request(ChatConversation.self, method: "PATCH", path: route(id), body: ["pinned": pinned]), expectedID: id)
    }
    public func setProfile(id: Int64, profileID: Int64?) async throws {
        let result = try await request(Acknowledgement.self, method: "PATCH", path: route(id) + "/profile", body: ["llm_profile_id": profileValue(profileID)])
        guard result.ok else { throw BackendAPIError.invalidResponse }
    }
    public func delete(id: Int64) async throws {
        let result = try await request(Deleted.self, method: "DELETE", path: route(id))
        guard result.deleted == id else { throw BackendAPIError.invalidResponse }
    }
    public func deleteBatch(ids: [Int64]) async throws -> [ChatDeleteResult] {
        var seen: Set<Int64> = []; let unique = ids.filter { seen.insert($0).inserted }
        guard !unique.isEmpty, unique.count <= 100, unique.allSatisfy({ $0 > 0 }) else { throw BackendAPIError.invalidResponse }
        let result = try await request(Batch.self, method: "POST", path: "/api/conversations/delete/batch", body: ["ids": unique]).items
        guard result.count == unique.count, Set(result.map(\.id)) == seen else { throw BackendAPIError.invalidResponse }
        return result
    }
    public func history(id: Int64, before: Int64 = 0) async throws -> ChatPage {
        guard before >= 0 else { throw BackendAPIError.invalidResponse }
        let query = before > 0 ? "?limit=200&before=\(before)" : "?limit=200"
        return try await request(ChatPage.self, path: route(id) + "/messages" + query)
    }
    public func delta(id: Int64, since: Int64) async throws -> ChatPage {
        guard since >= 0 else { throw BackendAPIError.invalidResponse }
        return try await request(ChatPage.self, path: route(id) + "/messages?since=\(since)")
    }
    public func detail(id: Int64, sequence: Int64) async throws -> String {
        guard sequence > 0 else { throw BackendAPIError.invalidResponse }
        return try await request(Detail.self, path: route(id) + "/messages/\(sequence)").detail ?? ""
    }
    public func send(id: Int64, message: String, attachments: [ChatAttachment] = []) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { throw BackendAPIError.validation("メッセージを入力してください。") }
        var body: [String: Any] = ["message": message]
        if !attachments.isEmpty { body["attachments"] = attachments.map(\.json) }
        let result = try await request(Status.self, method: "POST", path: route(id) + "/messages", body: body)
        guard result.status == "accepted" else { throw BackendAPIError.invalidResponse }
    }
    public func stop(id: Int64) async throws -> ChatStopStatus {
        try await request(Stop.self, method: "POST", path: route(id) + "/stop", body: [:]).status
    }
}
