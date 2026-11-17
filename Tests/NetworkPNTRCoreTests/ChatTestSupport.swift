import Foundation
@testable import NetworkPNTRCore

@MainActor final class ChatTestTransport: BackendJSONTransport {
    struct Call { let method: String; let path: String; let body: Data? }
    var calls: [Call] = []
    var replies: [BackendHTTPResponse] = []
    var handler: ((Call) async throws -> BackendHTTPResponse)?
    func enqueue(_ object: Any, status: Int = 200) throws {
        replies.append(try Self.response(object, status: status))
    }
    static func response(_ object: Any, status: Int = 200) throws -> BackendHTTPResponse {
        .init(status: status, body: try JSONSerialization.data(withJSONObject: object))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        guard bearer == nil else { throw BackendAPIError.invalidResponse }
        let call = Call(method: method, path: path, body: body); calls.append(call)
        if let handler { return try await handler(call) }
        guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }
        return replies.removeFirst()
    }
}

enum ChatFixture {
    static func conversation(_ id: Int64 = 7, title: String = "fixture", running: Bool = false) -> [String: Any] {
        ["id": id, "agent_key": "auto", "title": title, "created_at": "2026-10-23T00:00:00Z", "updated_at": "2026-10-23T00:00:00Z", "running": running]
    }
    static func event(_ seq: Int64, summary: String = "fixture") -> [String: Any] {
        ["seq": seq, "worker": "auto", "ts": "2026-10-23T00:00:00Z", "kind": "text", "summary": summary]
    }
    static func page(_ sequences: [Int64], cursor: Int64, running: Bool = false, hasMore: Bool = false) -> [String: Any] {
        ["items": sequences.map { event($0) }, "cursor": cursor, "running": running, "hasMore": hasMore]
    }
}
