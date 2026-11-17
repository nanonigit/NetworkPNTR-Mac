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

private struct WorkspaceUploadResult: Sendable {
    let conversationID: Int64
    let created: ChatConversation?
    let attachments: [ChatAttachment]
}
@MainActor private final class WorkspaceUploadOperation {
    let id = UUID()
    let origin: Int64
    var target: Int64?
    var worker: Task<WorkspaceUploadResult, Error>?
    var pump: Task<Void, Never>?
    let stream: AsyncStream<BackendUploadProgress>
    let continuation: AsyncStream<BackendUploadProgress>.Continuation
    init(origin: Int64, target: Int64?) {
        self.origin = origin; self.target = target
        let channel = AsyncStream<BackendUploadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = channel.stream; continuation = channel.continuation
    }
    func cancel() { worker?.cancel(); pump?.cancel(); continuation.finish() }
}

@MainActor @Observable public final class ChatWorkspace {
    public let transcript: ChatStore
    public let mentionService: ChatMentionService
    public private(set) var agents: [ChatAgent] = []
    public private(set) var profiles: [LLMProfile] = []
    public var agentKey = ""
    public var draftProfileID: Int64?
    public private(set) var busy = false
    public private(set) var loading = false
    public var error: String? { failure?.text(language: .japanese) }
    public private(set) var failure: AppErrorMessage?
    private var uploadStates: [Int64: ChatAttachmentUploadState] = [:]
    private var uploadErrors: [Int64: AppErrorMessage] = [:]
    @ObservationIgnored private var uploadOperations: [Int64: WorkspaceUploadOperation] = [:]
    @ObservationIgnored private var deletingIDs: Set<Int64> = []
    @ObservationIgnored private let client: any BackendJSONTransport
    @ObservationIgnored private let service: ChatService
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var selection = UUID()
    public init(client: any BackendJSONTransport) {
        self.client = client; service = ChatService(client: client); transcript = ChatStore(service: service)
        mentionService = ChatMentionService(client: client)
    }
    public var selected: ChatConversation? { transcript.conversations.first { $0.id == transcript.selectedID } }
    public func name(for key: String) -> String { agents.first { $0.key == key }?.name ?? key }
    private func message(_ error: any Error) -> AppErrorMessage { AppErrorMessage(error) }
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
            agents = loaded.filter(\.isChatEligible); self.profiles = profiles; failure = nil
            if agentKey.isEmpty, agents.contains(where: { $0.key == "auto" }) { agentKey = "auto" }
        } catch { if ticket == lifetime, !Task.isCancelled { self.failure = message(error) } }
    }
    public func select(_ id: Int64?) async {
        selection = UUID(); failure = nil
        await transcript.select(id: id)
    }
    public func send() async -> Bool {
        guard !busy, !isUploading, !ChatText.trim(transcript.draft).isEmpty || !transcript.attachments.isEmpty else { return false }
        if transcript.selectedID != nil { return await transcript.sendCurrentDraft() }
        guard !agentKey.isEmpty else { return false }
        let life = lifetime; let ticket = selection; let submitted = transcript.draft
        busy = true; failure = nil
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
            if life == lifetime, ticket == selection, !Task.isCancelled { self.failure = message(error) }
            return false
        }
    }
    public var isUploading: Bool { uploadState(for: transcript.selectedID) != nil }
    public var uploadFailure: AppErrorMessage? { uploadErrors[transcript.selectedID ?? 0] }
    public var uploadError: String? { uploadFailure?.text(language: .japanese) }
    public func uploadState(for id: Int64?) -> ChatAttachmentUploadState? {
        let key = id ?? 0
        return uploadStates[key] ?? uploadStates.values.first { $0.conversationID == id && id != nil }
    }
    public func cancelUpload(for id: Int64?, operationID: UUID? = nil) {
        let key = id ?? 0
        for operation in Array(uploadOperations.values) where operation.origin == key || operation.target == id && id != nil {
            guard operationID == nil || operationID == operation.id else { continue }
            operation.cancel(); finishUpload(origin: operation.origin, id: operation.id)
        }
    }
    private func finishUpload(origin: Int64, id: UUID) {
        guard let operation = uploadOperations[origin], operation.id == id else { return }
        operation.pump?.cancel(); operation.continuation.finish()
        uploadOperations.removeValue(forKey: origin); uploadStates.removeValue(forKey: origin)
    }
    private func noteCreatedUpload(_ conversation: ChatConversation, origin: Int64, id: UUID, life: UUID) -> Bool {
        guard life == lifetime, let operation = uploadOperations[origin], operation.id == id,
              !deletingIDs.contains(conversation.id), operation.worker?.isCancelled != true else { return false }
        operation.target = conversation.id
        uploadStates[origin] = ChatAttachmentUploadState(operationID: id, conversationID: conversation.id, progress: uploadStates[origin]?.progress)
        uploadErrors[conversation.id] = nil
        transcript.registerCreatedConversation(conversation)
        return true
    }
    private func receiveUploadProgress(_ value: BackendUploadProgress, origin: Int64, id: UUID, life: UUID) {
        guard life == lifetime, let operation = uploadOperations[origin], operation.id == id,
              operation.worker?.isCancelled != true, !Task.isCancelled else { return }
        uploadStates[origin] = ChatAttachmentUploadState(operationID: id, conversationID: operation.target, progress: value)
    }
    public func pickFiles(_ files: [URL]) async -> Bool {
        let originID = transcript.selectedID, origin = originID ?? 0
        guard !Task.isCancelled, !files.isEmpty, !busy, !isUploading, !transcript.isSending,
              !deletingIDs.contains(origin), originID != nil || !agentKey.isEmpty else { return false }
        guard let uploader = client as? any ChatAttachmentUploading else {
            uploadErrors[origin] = AppErrorMessage(key: .errorUploadUnavailable); return false
        }
        let life = lifetime, selected = selection, capturedText = transcript.draft(for: nil)
        let capturedRevision = transcript.draftRevision(for: nil), agent = agentKey, profile = draftProfileID
        let operation = WorkspaceUploadOperation(origin: origin, target: originID)
        let identifier = operation.id, stream = operation.stream, continuation = operation.continuation
        uploadOperations[origin] = operation; uploadErrors[origin] = nil
        uploadStates[origin] = ChatAttachmentUploadState(operationID: identifier, conversationID: originID, progress: nil)
        let createdCallback: @MainActor @Sendable (ChatConversation) -> Bool = { [weak self] conversation in
            self?.noteCreatedUpload(conversation, origin: origin, id: identifier, life: life) ?? false
        }
        let service = service
        let worker = Task { @MainActor in
            try Task.checkCancellation()
            let created: ChatConversation?
            if originID == nil {
                let conversation = try await service.create(agentKey: agent, profileID: profile)
                try Task.checkCancellation()
                guard createdCallback(conversation) else { throw CancellationError() }
                created = conversation
            } else { created = nil }
            guard let target = originID ?? created?.id else { throw BackendAPIError.invalidResponse }
            let attachments = try await uploader.uploadAttachments(conversationID: target, files: files, progress: { continuation.yield($0) })
            try Task.checkCancellation()
            guard !attachments.isEmpty, attachments.count == files.count else { throw BackendAPIError.invalidResponse }
            return WorkspaceUploadResult(conversationID: target, created: created, attachments: attachments)
        }
        operation.worker = worker
        operation.pump = Task { @MainActor [weak self] in
            for await value in stream { self?.receiveUploadProgress(value, origin: origin, id: identifier, life: life) }
        }
        defer { finishUpload(origin: origin, id: identifier) }
        do {
            let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel(); continuation.finish() }
            guard life == lifetime, uploadOperations[origin]?.id == identifier, !Task.isCancelled,
                  !deletingIDs.contains(result.conversationID) else { return false }
            try transcript.appendAttachments(result.attachments, for: result.conversationID)
            if result.created != nil {
                let sameSelection = selected == selection && transcript.selectedID == nil
                let text = sameSelection ? transcript.draft(for: nil) : capturedText
                let revision = sameSelection ? transcript.draftRevision(for: nil) : capturedRevision
                transcript.handoffDraft(text, to: result.conversationID, sourceRevision: revision)
                if sameSelection { await transcript.select(id: result.conversationID) }
            }
            await transcript.refreshList()
            return life == lifetime && uploadOperations[origin]?.id == identifier && !Task.isCancelled
        } catch {
            if life == lifetime, uploadOperations[origin]?.id == identifier, !Task.isCancelled, !(error is CancellationError) {
                let text = message(error); uploadErrors[origin] = text
                if let target = operation.target { uploadErrors[target] = text }
            }
            return false
        }
    }
    private func mutate(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        let ticket = lifetime; busy = true; failure = nil
        defer { if ticket == lifetime { busy = false } }
        do {
            try await operation()
            guard ticket == lifetime, !Task.isCancelled else { return }
            await transcript.refreshList()
        } catch { if ticket == lifetime, !Task.isCancelled { self.failure = message(error) } }
    }
    public func rename(id: Int64, title: String) async { await mutate { _ = try await service.rename(id: id, title: title) } }
    public func pin(id: Int64, pinned: Bool) async { await mutate { _ = try await service.pin(id: id, pinned: pinned) } }
    public func changeProfile(id: Int64, profileID: Int64?) async { await mutate { try await service.setProfile(id: id, profileID: profileID) } }
    public func delete(ids: [Int64]) async -> [ChatDeleteResult] {
        guard !busy else { return [] }
        let ticket = lifetime; busy = true; failure = nil
        deletingIDs.formUnion(ids)
        for id in ids { cancelUpload(for: id) }
        defer { if ticket == lifetime { busy = false; deletingIDs.subtract(ids) } }
        do {
            let result = try await service.deleteBatch(ids: ids)
            guard ticket == lifetime, !Task.isCancelled else { return [] }
            let removedSelection = result.contains { $0.ok && $0.id == transcript.selectedID }
            for item in result where item.ok { transcript.forgetConversation(item.id); uploadErrors[item.id] = nil }
            if removedSelection { await select(nil) }
            if result.contains(where: { !$0.ok }) { failure = AppErrorMessage(key: .errorPartialDelete) }
            await transcript.refreshList()
            return result
        } catch { if ticket == lifetime, !Task.isCancelled { self.failure = message(error) }; return [] }
    }
    public func detail(id: Int64, sequence: Int64) async throws -> String { try await service.detail(id: id, sequence: sequence) }
    public func stop() {
        for operation in Array(uploadOperations.values) { operation.cancel(); finishUpload(origin: operation.origin, id: operation.id) }
        lifetime = UUID(); selection = UUID(); deletingIDs = []; busy = false; loading = false; transcript.stop()
    }
    public func reset() { stop(); transcript.reset(); uploadErrors = [:]; failure = nil }
}
