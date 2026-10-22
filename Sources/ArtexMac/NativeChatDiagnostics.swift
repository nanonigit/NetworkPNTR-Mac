#if DEBUG
import ArtexCore
import Foundation

/// Fixed, developer-only CRUD acceptance on the disposable authenticated VM.
@MainActor enum NativeChatDiagnostics {
    static func run(session: AuthenticationSession, directory: URL) async throws {
        let service = ChatService(client: AuthenticatedBackendClient(session: session))
        guard try await service.conversations().isEmpty else { throw RuntimeError.integrity("fresh chat fixture database") }
        let profiles = try await LLMService(client: AuthenticatedBackendClient(session: session)).profiles()
        guard let active = profiles.first(where: { $0.isDefault }), let profileID = Int64(active.id) else {
            throw RuntimeError.integrity("chat fixture active profile")
        }
        struct Agents: Decodable { struct Agent: Decodable { let key: String }; let agents: [Agent] }
        let agentsResponse = try await session.authenticatedRequest(method: "GET", path: "/api/agents")
        guard agentsResponse.status == 200,
              let key = try BackendJSONCoding.decode(Agents.self, from: agentsResponse.body).agents.map(\.key).sorted().first else {
            throw RuntimeError.integrity("chat fixture agent")
        }
        let created = try await service.create(agentKey: key, title: "Native chat fixture", profileID: profileID)
        guard created.title == "Native chat fixture", created.llmProfileId == profileID else { throw RuntimeError.integrity("chat create") }
        let renamed = try await service.rename(id: created.id, title: "Native chat renamed")
        let pinned = try await service.pin(id: created.id, pinned: true)
        let unpinned = try await service.pin(id: created.id, pinned: false)
        guard renamed.title == "Native chat renamed", pinned.isPinned, !unpinned.isPinned else { throw RuntimeError.integrity("chat rename and pin") }
        try await service.setProfile(id: created.id, profileID: nil)
        let cleared = try await service.conversations()
        guard cleared.count == 1, cleared.first?.llmProfileId == nil else { throw RuntimeError.integrity("chat profile clear") }
        try await service.setProfile(id: created.id, profileID: profileID)
        let restored = try await service.conversations()
        guard restored.first?.llmProfileId == profileID else { throw RuntimeError.integrity("chat profile restore") }
        let history = try await service.history(id: created.id)
        let delta = try await service.delta(id: created.id, since: 0)
        let detail = try await service.detail(id: created.id, sequence: 9999999)
        let stop = try await service.stop(id: created.id)
        guard history.items.isEmpty, delta.items.isEmpty, !history.running, !delta.running,
              detail.isEmpty, stop == .idle else { throw RuntimeError.integrity("chat empty transcript and idle stop") }
        let emptySend = try await session.authenticatedRequest(method: "POST", path: "/api/conversations/\(created.id)/messages",
            body: JSONSerialization.data(withJSONObject: ["message": ""]))
        let invalidProfile = try await session.authenticatedRequest(method: "PATCH", path: "/api/conversations/\(created.id)/profile",
            body: JSONSerialization.data(withJSONObject: ["llm_profile_id": 9999999]))
        guard emptySend.status == 400, invalidProfile.status == 400 else { throw RuntimeError.integrity("chat negative validation") }
        let batch = try await service.deleteBatch(ids: [created.id, 9999999, created.id])
        guard batch.count == 2, batch.first(where: { $0.id == created.id })?.ok == true,
              batch.first(where: { $0.id == 9999999 })?.ok == false else { throw RuntimeError.integrity("chat partial batch delete") }
        let other = try await service.create(agentKey: key, title: "Native chat cleanup")
        try await service.delete(id: other.id)
        guard try await service.conversations().isEmpty else { throw RuntimeError.integrity("chat cleanup") }
        let contract: [String: Any] = ["created_title": created.title, "renamed_title": renamed.title,
            "pin_roundtrip": pinned.isPinned && !unpinned.isPinned, "profile_clear_restore": true,
            "empty_history": history.items.isEmpty, "empty_delta": delta.items.isEmpty, "missing_detail_empty": detail.isEmpty,
            "idle_stop": stop.rawValue, "empty_send_status": emptySend.status, "invalid_profile_status": invalidProfile.status,
            "batch_existing_ok": true, "batch_missing_ok": false, "batch_deduplicated_count": batch.count,
            "single_delete_and_cleanup": true]
        try JSONSerialization.data(withJSONObject: contract, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("chat-contract-vm.json"))
    }
}
#endif
