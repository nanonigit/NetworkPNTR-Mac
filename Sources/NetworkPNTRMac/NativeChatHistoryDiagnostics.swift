#if DEBUG
import NetworkPNTRCore
import Foundation

/// Fixed fixture only. Exercises production history services/store with no AI execution.
@MainActor enum NativeChatHistoryDiagnostics {
    struct Snapshot {
        let conversationID: Int64
        let firstSequence: Int64
        let messages: [ChatActivity]
        let contract: [String: Any]
    }
    private static func seed(session: AuthenticationSession, phase: String) async throws {
        guard ["initial", "append"].contains(phase) else { throw RuntimeError.integrity("chat seed phase") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("script/chat_history_seed_guest.py"), encoding: .utf8)
        // Only a fixed checked-in script and enum-like phase are allowed in this debug harness.
        let code = source.replacingOccurrences(of: "if __name__ == '__main__':\n    main()", with: "if __name__ == '__main__':\n    main('\(phase)')")
        let body = try JSONSerialization.data(withJSONObject: ["kind": "script", "exec": ["code": code, "timeout_ms": 20_000], "params": [:]])
        let response = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: body)
        guard response.status == 200,
              let result = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              result["is_error"] as? Bool == false, let output = result["output"] as? String,
              let data = output.data(using: .utf8), let proof = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              proof["chat_history_seeded"] as? String == phase, proof["linux_guest"] as? Bool == true,
              proof["aarch64"] as? Bool == true, proof["uid"] as? Int == 1000 else {
            throw RuntimeError.integrity("chat history seed proof")
        }
    }
    static func run(session: AuthenticationSession, directory: URL) async throws -> Snapshot {
        let service = ChatService(client: AuthenticatedBackendClient(session: session))
        guard try await service.conversations().isEmpty else { throw RuntimeError.integrity("fresh populated chat database") }
        struct Agents: Decodable { struct Agent: Decodable { let key: String }; let agents: [Agent] }
        let response = try await session.authenticatedRequest(method: "GET", path: "/api/agents")
        guard response.status == 200,
              let key = try BackendJSONCoding.decode(Agents.self, from: response.body).agents.map(\.key).sorted().first else {
            throw RuntimeError.integrity("history fixture agent")
        }
        let conversation = try await service.create(agentKey: key, title: "Native chat history fixture")
        try await seed(session: session, phase: "initial")
        let latest = try await service.history(id: conversation.id)
        guard latest.items.count == 200, latest.hasMore, !latest.running else { throw RuntimeError.integrity("latest history page") }
        let store = ChatStore(service: service)
        await store.select(id: conversation.id)
        guard store.messages == latest.items, store.hasMore else { throw RuntimeError.integrity("history store initial page") }
        let latestCursor = store.cursor
        await store.loadOlder()
        let initial = store.messages
        guard initial.count == 205, !store.hasMore, store.cursor == latestCursor, let first = initial.first,
              initial.map(\.seq) == (0..<205).map({ first.seq + Int64($0) }),
              initial.allSatisfy({ $0.detail == nil }), initial[3].kind == "future_fixture_kind",
              initial[1].toolUseId == "fixture-call", initial[2].toolUseId == "fixture-call",
              initial[1].tool == "fixture-tool", initial[2].tool == "fixture-tool",
              initial.last?.inputTokens == 100, initial.last?.outputTokens == 10 else {
            throw RuntimeError.integrity("populated history merge, lazy detail and event payloads")
        }
        let detail = try await service.detail(id: conversation.id, sequence: first.seq)
        guard detail == String(repeating: "guest fixture detail ", count: 512) else { throw RuntimeError.integrity("lazy full detail") }
        let overlap = try await service.delta(id: conversation.id, since: initial[199].seq)
        guard overlap.items.map(\.seq) == initial.suffix(5).map(\.seq),
              ChatTranscript.merge(initial, incoming: overlap.items) == initial else { throw RuntimeError.integrity("overlapping history delta") }
        try await seed(session: session, phase: "append")
        // A foreground resume reconciles the final tail even when server running=false.
        store.stop(); await store.refreshDelta()
        guard store.messages.count == 211, store.cursor == first.seq + 210, !store.running,
              !store.needsTailReconciliation, store.messages.suffix(6).map(\.summary) == (206...211).map({ "fixture event \($0)" }) else {
            throw RuntimeError.integrity("post-resume final idle delta")
        }
        let other = try await service.create(agentKey: key, title: "History scope check")
        let crossDetail = try await service.detail(id: other.id, sequence: first.seq)
        guard crossDetail.isEmpty else { throw RuntimeError.integrity("conversation detail scope") }
        try await service.delete(id: other.id)
        guard try await service.conversations().map(\.id) == [conversation.id] else { throw RuntimeError.integrity("history fixture retained for restart") }
        let contract: [String: Any] = ["latest_count": latest.items.count, "latest_has_more": latest.hasMore,
            "older_count": initial.count - latest.items.count, "older_has_more": false, "initial_total": initial.count,
            "initial_cursor_offset": latestCursor - first.seq, "lazy_details_omitted": initial.allSatisfy({ $0.detail == nil }),
            "detail_utf8_bytes": detail.utf8.count, "event_kinds": Set(initial.map(\.kind)).sorted(),
            "tool_pair_preserved": true, "result_input_tokens": initial.last?.inputTokens ?? 0,
            "result_output_tokens": initial.last?.outputTokens ?? 0, "overlap_count": overlap.items.count,
            "overlap_deduplicated": true, "final_total": store.messages.count, "final_cursor_offset": store.cursor - first.seq,
            "final_summaries": store.messages.suffix(6).map(\.summary), "final_running": store.running,
            "cross_conversation_detail_empty": crossDetail.isEmpty, "cleanup": true]
        return Snapshot(conversationID: conversation.id, firstSequence: first.seq, messages: store.messages, contract: contract)
    }
    static func verifyPersistence(_ snapshot: Snapshot, session: AuthenticationSession, directory: URL) async throws {
        let service = ChatService(client: AuthenticatedBackendClient(session: session))
        let store = ChatStore(service: service)
        await store.select(id: snapshot.conversationID)
        guard store.messages.count == 200, store.hasMore else { throw RuntimeError.integrity("post-restart latest history") }
        await store.loadOlder()
        guard store.messages == snapshot.messages, !store.hasMore,
              store.cursor == snapshot.firstSequence + 210,
              try await service.detail(id: snapshot.conversationID, sequence: snapshot.firstSequence) == String(repeating: "guest fixture detail ", count: 512) else {
            throw RuntimeError.integrity("post-restart complete history and detail")
        }
        try await service.delete(id: snapshot.conversationID)
        guard try await service.conversations().isEmpty else { throw RuntimeError.integrity("post-restart history cleanup") }
        try JSONSerialization.data(withJSONObject: snapshot.contract, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("chat-history-contract-vm.json"))
    }
}
#endif
