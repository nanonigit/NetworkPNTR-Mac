import Foundation
import Observation

@MainActor @Observable public final class ChatStore {
    public private(set) var conversations: [ChatConversation] = []
    public private(set) var selectedID: Int64?
    public private(set) var messages: [ChatActivity] = []
    public private(set) var cursor: Int64 = 0
    public private(set) var hasMore = false
    public private(set) var hasLoadedHistory = false
    public private(set) var running = false
    public private(set) var needsTailReconciliation = false
    public private(set) var isLoadingList = false
    public private(set) var isLoadingHistory = false
    public private(set) var isLoadingOlder = false
    public private(set) var isLoadingDelta = false
    public private(set) var listError: String?
    public private(set) var transcriptError: String?
    public private(set) var stopStatus: ChatStopStatus?
    private var drafts: [Int64: String] = [:]
    private var attachmentDrafts: [Int64: [ChatAttachment]] = [:]
    @ObservationIgnored private var draftRevisions: [Int64: UUID] = [:]
    @ObservationIgnored private var pendingSends: [Int64: PendingSend] = [:]
    private struct PendingSend {
        let text: String?
        let clearedTextRevision: UUID?
        let attachments: [ChatAttachment]
    }
    private var mutationErrors: [Int64: String] = [:]
    private var sendingIDs: Set<Int64> = []
    private var stoppingIDs: Set<Int64> = []
    @ObservationIgnored private let service: ChatService
    @ObservationIgnored private let pause: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var selection = UUID()
    @ObservationIgnored private var tailRevision = UUID()
    @ObservationIgnored private var listPolling = false
    @ObservationIgnored private var tailPolling = false

    public init(service: ChatService, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service; pause = sleep
    }
    public var draft: String {
        get { draft(for: selectedID) }
        set { setDraft(newValue, for: selectedID) }
    }
    public func draft(for id: Int64?) -> String { drafts[id ?? 0] ?? "" }
    public func setDraft(_ value: String, for id: Int64?) {
        drafts[id ?? 0] = value; draftRevisions[id ?? 0] = UUID()
    }
    public var attachments: [ChatAttachment] { attachments(for: selectedID) }
    public func attachments(for id: Int64?) -> [ChatAttachment] { id.flatMap { attachmentDrafts[$0] } ?? [] }
    public func appendAttachments(_ values: [ChatAttachment], for id: Int64) throws {
        let current = attachments(for: id), paths = Set(values.map(\.id))
        guard id > 0, paths.count == values.count, paths.isDisjoint(with: current.map(\.id)) else { throw BackendAPIError.invalidResponse }
        attachmentDrafts[id] = current + values
    }
    /// Removing a draft card never deletes the already uploaded guest file.
    public func removeAttachment(path: String, for id: Int64) {
        guard id > 0 else { return }
        attachmentDrafts[id] = attachments(for: id).filter { !$0.path.utf8.elementsEqual(path.utf8) }
    }
    private func restorePendingSend(_ id: Int64) {
        guard let pending = pendingSends.removeValue(forKey: id) else { return }
        if let text = pending.text, draftRevisions[id] == pending.clearedTextRevision { setDraft(text, for: id) }
        let current = attachments(for: id), paths = Set(current.map(\.id))
        attachmentDrafts[id] = pending.attachments.filter { !paths.contains($0.id) } + current
    }
    public var isSending: Bool { selectedID.map(sendingIDs.contains) ?? false }
    public var isStopping: Bool { selectedID.map(stoppingIDs.contains) ?? false }
    public var mutationError: String? { selectedID.flatMap { mutationErrors[$0] } }
    private func safeMessage(_ error: any Error) -> String {
        (error as? BackendAPIError)?.localizedDescription ?? "実行環境との通信を確認してください。"
    }
    private func current(_ life: UUID, _ ticket: UUID, _ id: Int64) -> Bool {
        life == lifetime && ticket == selection && id == selectedID && !Task.isCancelled
    }
    private func advanceCursor(_ page: ChatPage) {
        cursor = max(cursor, max(page.cursor, page.items.map(\.seq).max() ?? 0))
    }
    private func requireTailReconciliation(newTurn: Bool = false) {
        tailRevision = UUID(); needsTailReconciliation = true
        if newTurn { running = true }
    }
    public func refreshList() async {
        guard !isLoadingList else { return }
        let ticket = lifetime; isLoadingList = true
        defer { if ticket == lifetime { isLoadingList = false } }
        do {
            let items = try await service.conversations()
            guard ticket == lifetime, !Task.isCancelled else { return }
            conversations = items; listError = nil
            // A stale false list snapshot must not terminate the selected transcript tail.
            if let id = selectedID, !running, items.first(where: { $0.id == id })?.isRunning == true {
                requireTailReconciliation(newTurn: true)
            }
        } catch {
            if ticket == lifetime, !Task.isCancelled, !(error is CancellationError) { listError = safeMessage(error) }
        }
    }
    public func select(id: Int64?, draft: String? = nil) async {
        if let id, id <= 0 { return }
        if id == selectedID {
            if id != nil, !hasLoadedHistory, !isLoadingHistory { await loadLatest() }
            return
        }
        selection = UUID(); tailPolling = false
        selectedID = id; messages = []; cursor = 0; hasMore = false; hasLoadedHistory = false
        running = id.flatMap { selected in conversations.first(where: { $0.id == selected })?.isRunning } ?? false
        needsTailReconciliation = false; stopStatus = nil; transcriptError = nil
        isLoadingHistory = false; isLoadingOlder = false; isLoadingDelta = false
        if let draft { setDraft(draft, for: id) }
        if id != nil { await loadLatest() }
    }
    private func loadLatest() async {
        guard let id = selectedID, !isLoadingHistory else { return }
        let life = lifetime; let ticket = selection; isLoadingHistory = true
        defer { if life == lifetime, ticket == selection { isLoadingHistory = false } }
        do {
            let page = try await service.history(id: id)
            guard current(life, ticket, id) else { return }
            messages = ChatTranscript.merge([], incoming: page.items); advanceCursor(page)
            hasMore = page.hasMore; running = running || page.running; hasLoadedHistory = true; transcriptError = nil
        } catch {
            if current(life, ticket, id), !(error is CancellationError) { transcriptError = safeMessage(error) }
        }
    }
    public func loadOlder() async {
        guard let id = selectedID, hasLoadedHistory, hasMore, !isLoadingHistory, !isLoadingOlder,
              let before = messages.first?.seq else { return }
        let life = lifetime; let ticket = selection; isLoadingOlder = true
        defer { if life == lifetime, ticket == selection { isLoadingOlder = false } }
        do {
            let page = try await service.history(id: id, before: before)
            guard current(life, ticket, id) else { return }
            messages = ChatTranscript.merge(page.items, incoming: messages)
            hasMore = page.hasMore; advanceCursor(page); transcriptError = nil
        } catch {
            if current(life, ticket, id), !(error is CancellationError) { transcriptError = safeMessage(error) }
        }
    }
    public func refreshDelta() async {
        guard let id = selectedID, hasLoadedHistory, !isLoadingHistory, !isLoadingDelta,
              running || needsTailReconciliation else { return }
        let life = lifetime; let ticket = selection; isLoadingDelta = true
        defer { if life == lifetime, ticket == selection { isLoadingDelta = false } }
        do {
            while current(life, ticket, id) {
                let revision = tailRevision
                let page = try await service.delta(id: id, since: cursor)
                guard current(life, ticket, id) else { return }
                messages = ChatTranscript.merge(messages, incoming: page.items); advanceCursor(page)
                transcriptError = nil
                // A response begun before an accepted mutation cannot settle its newer tail.
                // Keep the single request slot and fetch again after that response completes.
                if revision != tailRevision { continue }
                running = page.running
                // Upstream caps a delta at 1000 events even when running=false. Drain a full final burst.
                needsTailReconciliation = page.items.count >= 1000
                if !running, !needsTailReconciliation { stopStatus = nil }
                return
            }
        } catch {
            if current(life, ticket, id), !(error is CancellationError) { transcriptError = safeMessage(error) }
        }
    }

    public func sendCurrentDraft(submittedMessage: String? = nil) async -> Bool {
        guard let id = selectedID, hasLoadedHistory, !isLoadingHistory, !sendingIDs.contains(id) else { return false }
        let submitted = submittedMessage ?? drafts[id] ?? "", cards = attachments(for: id)
        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !cards.isEmpty else { return false }
        let ticket = lifetime
        let clearsText = draft(for: id) == submitted
        if clearsText { setDraft("", for: id) }
        pendingSends[id] = PendingSend(text: clearsText ? submitted : nil,
            clearedTextRevision: clearsText ? draftRevisions[id] : nil, attachments: cards)
        attachmentDrafts[id] = []
        sendingIDs.insert(id); mutationErrors[id] = nil
        defer { if ticket == lifetime { sendingIDs.remove(id) } }
        do {
            try await service.send(id: id, message: submitted, attachments: cards)
            guard ticket == lifetime else { return false }
            guard !Task.isCancelled else { restorePendingSend(id); return false }
            pendingSends.removeValue(forKey: id)
            if selectedID == id { requireTailReconciliation(newTurn: true); stopStatus = nil }
            // Confirmation stays successful even if a subsequent refresh fails.
            await refreshList()
            if ticket == lifetime, !Task.isCancelled, selectedID == id { await refreshDelta() }
            return true
        } catch {
            if ticket == lifetime {
                restorePendingSend(id)
                if !Task.isCancelled, !(error is CancellationError) { mutationErrors[id] = safeMessage(error) }
            }
            return false
        }
    }
    public func requestStop() async -> Bool {
        guard let id = selectedID, !stoppingIDs.contains(id) else { return false }
        let ticket = lifetime; stoppingIDs.insert(id); mutationErrors[id] = nil
        defer { if ticket == lifetime { stoppingIDs.remove(id) } }
        do {
            let status = try await service.stop(id: id)
            guard ticket == lifetime, !Task.isCancelled else { return false }
            if selectedID == id { stopStatus = status; requireTailReconciliation(); await refreshDelta() }
            return true
        } catch {
            if ticket == lifetime, !Task.isCancelled, !(error is CancellationError) { mutationErrors[id] = safeMessage(error) }
            return false
        }
    }
    /// The caller owns/cancels the structured task; no store-to-task retain cycle is created.
    public func pollList() async {
        guard !listPolling else { return }
        let ticket = lifetime; listPolling = true
        defer { if ticket == lifetime { listPolling = false } }
        while ticket == lifetime, !Task.isCancelled {
            await refreshList()
            guard ticket == lifetime, !Task.isCancelled else { return }
            do { try await pause(.seconds(2)) } catch { return }
        }
    }
    public func pollSelected() async {
        guard selectedID != nil, !tailPolling else { return }
        let life = lifetime; let ticket = selection; tailPolling = true
        defer { if life == lifetime, ticket == selection { tailPolling = false } }
        while life == lifetime, ticket == selection, !Task.isCancelled {
            await refreshDelta()
            guard life == lifetime, ticket == selection, !Task.isCancelled else { return }
            do { try await pause(.seconds(1)) } catch { return }
        }
    }
    /// Invalidates local work; it does not claim to cancel an already accepted server action.
    public func stop() {
        for id in Array(pendingSends.keys) { restorePendingSend(id) }
        lifetime = UUID(); selection = UUID(); listPolling = false; tailPolling = false
        isLoadingList = false; isLoadingHistory = false; isLoadingOlder = false; isLoadingDelta = false
        sendingIDs = []; stoppingIDs = []; running = false
        needsTailReconciliation = selectedID != nil && hasLoadedHistory; stopStatus = nil
    }
    public func reset() {
        stop(); conversations = []; selectedID = nil; messages = []; cursor = 0
        hasLoadedHistory = false; hasMore = false; listError = nil; transcriptError = nil
        drafts = [:]; draftRevisions = [:]; attachmentDrafts = [:]; pendingSends = [:]
        mutationErrors = [:]; needsTailReconciliation = false
    }
}
