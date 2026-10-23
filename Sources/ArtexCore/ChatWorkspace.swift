import Foundation
import Observation

public struct ChatAgent: Decodable, Identifiable, Sendable {
    public let key: String
    public let name: String
    public let description: String
    public let builtin: Bool
    public let role: String
    public var id: String { key }
    public var isChatEligible: Bool { !builtin || role == "assistant" }
}
public enum ChatSendPolicy {
    public static func shouldSend(mode: String, shift: Bool, control: Bool, command: Bool, composing: Bool) -> Bool {
        guard !composing else { return false }
        return mode == "ctrl-enter" ? control || command : !shift
    }
}

@MainActor @Observable public final class ChatWorkspace {
    public let transcript: ChatStore
    public private(set) var agents: [ChatAgent] = []
    public private(set) var profiles: [LLMProfile] = []
    public var agentKey = ""
    public var draftProfileID: Int64?
    public private(set) var busy = false
    public private(set) var loading = false
    public private(set) var error: String?
    @ObservationIgnored private let client: any BackendJSONTransport
    @ObservationIgnored private let service: ChatService
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var selection = UUID()
    public init(client: any BackendJSONTransport) {
        self.client = client; service = ChatService(client: client); transcript = ChatStore(service: service)
    }
    public var selected: ChatConversation? { transcript.conversations.first { $0.id == transcript.selectedID } }
    public func name(for key: String) -> String { agents.first { $0.key == key }?.name ?? key }
    private func message(_ error: any Error) -> String {
        (error as? BackendAPIError)?.localizedDescription ?? "実行環境との通信を確認してください。"
    }
    public func load() async {
        guard !loading else { return }
        let ticket = lifetime; loading = true
        defer { if ticket == lifetime { loading = false } }
        do {
            struct Envelope: Decodable { let agents: [ChatAgent] }
            let response = try await client.send(method: "GET", path: "/api/agents", body: nil, bearer: nil)
            guard response.status == 200 else { throw BackendAPIError.status(response.status) }
            let loaded = try BackendJSONCoding.decode(Envelope.self, from: response.body).agents
            guard loaded.allSatisfy({ !$0.key.isEmpty }), Set(loaded.map(\.key)).count == loaded.count else { throw BackendAPIError.invalidResponse }
            let profiles = try await LLMService(client: client).profiles()
            guard ticket == lifetime, !Task.isCancelled else { return }
            agents = loaded.filter(\.isChatEligible); self.profiles = profiles; error = nil
            if agentKey.isEmpty, agents.contains(where: { $0.key == "auto" }) { agentKey = "auto" }
        } catch { if ticket == lifetime, !Task.isCancelled { self.error = message(error) } }
    }
    public func select(_ id: Int64?) async {
        selection = UUID(); error = nil
        await transcript.select(id: id)
    }
    public func send() async -> Bool {
        guard !busy, !transcript.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if transcript.selectedID != nil { return await transcript.sendCurrentDraft() }
        guard !agentKey.isEmpty else { return false }
        let life = lifetime; let ticket = selection; let submitted = transcript.draft
        busy = true; error = nil
        defer { if life == lifetime { busy = false } }
        do {
            let created = try await service.create(agentKey: agentKey, profileID: draftProfileID)
            guard life == lifetime, ticket == selection, !Task.isCancelled else { return false }
            let latestDraft = transcript.draft
            transcript.draft = ""
            await transcript.select(id: created.id, draft: latestDraft)
            guard life == lifetime, ticket == selection, !Task.isCancelled else { return false }
            let result = await transcript.sendCurrentDraft(submittedMessage: submitted)
            if life == lifetime, !Task.isCancelled { await transcript.refreshList() }
            return result
        } catch {
            if life == lifetime, ticket == selection, !Task.isCancelled { self.error = message(error) }
            return false
        }
    }
    private func mutate(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        let ticket = lifetime; busy = true; error = nil
        defer { if ticket == lifetime { busy = false } }
        do {
            try await operation()
            guard ticket == lifetime, !Task.isCancelled else { return }
            await transcript.refreshList()
        } catch { if ticket == lifetime, !Task.isCancelled { self.error = message(error) } }
    }
    public func rename(id: Int64, title: String) async { await mutate { _ = try await service.rename(id: id, title: title) } }
    public func pin(id: Int64, pinned: Bool) async { await mutate { _ = try await service.pin(id: id, pinned: pinned) } }
    public func changeProfile(id: Int64, profileID: Int64?) async { await mutate { try await service.setProfile(id: id, profileID: profileID) } }
    public func delete(ids: [Int64]) async -> [ChatDeleteResult] {
        guard !busy else { return [] }
        let ticket = lifetime; busy = true; error = nil
        defer { if ticket == lifetime { busy = false } }
        do {
            let result = try await service.deleteBatch(ids: ids)
            guard ticket == lifetime, !Task.isCancelled else { return [] }
            if result.contains(where: { $0.ok && $0.id == transcript.selectedID }) { await select(nil) }
            if result.contains(where: { !$0.ok }) { error = "一部の会話を削除できませんでした。残った会話を確認してください。" }
            await transcript.refreshList()
            return result
        } catch { if ticket == lifetime, !Task.isCancelled { self.error = message(error) }; return [] }
    }
    public func detail(id: Int64, sequence: Int64) async throws -> String { try await service.detail(id: id, sequence: sequence) }
    public func stop() { lifetime = UUID(); selection = UUID(); busy = false; loading = false; transcript.stop() }
}
