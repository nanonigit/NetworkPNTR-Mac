import ArtexCore
import Foundation
import Observation

/// Sheet-owned tasks never publish into a departed or edited draft.
@MainActor @Observable final class LLMEditorModel {
    var draft: LLMProfileDraft {
        didSet {
            guard !scrubbing else { return }
            if !active { scrubCredentials(includeProxy: true) }
            invalidateDraft()
            if oldValue.format != draft.format, draft.format != .openai, !draft.maxTokensField.isEmpty {
                scrubbing = true; draft.maxTokensField = ""; scrubbing = false
            }
        }
    }
    private(set) var invalidFields = Set<String>()
    private(set) var models: [String] = []
    var modelsOpen = false
    private(set) var testResult: LLMConnectionResult?
    private(set) var failure: AppErrorMessage?
    private(set) var didSave = false
    var isBusy: Bool { operation != nil }
    var loadingModels: Bool { operation?.kind == .models }
    var testing: Bool { operation?.kind == .test }
    var isSaving: Bool { operation?.kind == .save }
    var isActive: Bool { active }
    @ObservationIgnored private let store: LLMStore
    @ObservationIgnored private var active = true
    @ObservationIgnored private var activity = UUID()
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var acquiring = false
    @ObservationIgnored private var closing = false
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var task: Task<Void, Never>?
    private var operation: Ticket?
    private enum Kind { case models, test, save }
    private struct Ticket {
        let id = UUID()
        let activity, revision, parentActivity: UUID
        let kind: Kind
    }
    init(store: LLMStore, draft: LLMProfileDraft) { self.store = store; self.draft = draft }
    func mark(_ field: String, _ valid: Bool) {
        if valid { invalidFields.remove(field) }
        else { invalidFields.insert(field); invalidateDraft() }
    }
    private func invalidateDraft() {
        revision = UUID(); task?.cancel()
        models = []; modelsOpen = false; testResult = nil; failure = nil; didSave = false
    }
    private func scrubCredentials(includeProxy: Bool) {
        let previous = scrubbing; scrubbing = true
        defer { scrubbing = previous }
        draft.apiKey = ""
        if includeProxy || !active { draft.proxy = "" }
    }
    func close() {
        guard !closing, active else { return }
        closing = true
        defer { closing = false }
        active = false; activity = UUID()
        invalidateDraft(); scrubCredentials(includeProxy: true)
        // Keep the local operation gate until its uncooperative transport settles.
    }
    func activate() {
        guard !closing, !active else { return }
        activity = UUID(); active = true
    }
    private func owns(_ ticket: Ticket) -> Bool {
        active && store.isActive && ticket.parentActivity == store.activityID && ticket.activity == activity && ticket.revision == revision && operation?.id == ticket.id && !Task.isCancelled
    }
    @discardableResult func fetchModels() -> Bool { start(.models) }
    @discardableResult func testConnection() -> Bool { start(.test) }
    @discardableResult func save() -> Bool { start(.save) }
    private func start(_ kind: Kind) -> Bool {
        guard active, !closing, !acquiring, !isBusy, store.isActive, !store.isLoading, !store.isMutating, !Task.isCancelled,
              kind == .models || invalidFields.isEmpty,
              kind != .save || store.unknownRevision == nil else { return false }
        let snapshot = draft
        let ticket = Ticket(activity: activity, revision: revision, parentActivity: store.activityID, kind: kind)
        acquiring = true
        operation = ticket
        failure = nil; didSave = false
        if kind == .models { models = []; modelsOpen = false }
        if kind == .test { testResult = nil }
        acquiring = false
        guard owns(ticket) else {
            if operation?.id == ticket.id { operation = nil }
            return false
        }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(ticket, draft: snapshot)
        }
        return true
    }
    private func run(_ ticket: Ticket, draft: LLMProfileDraft) async {
        defer {
            if operation?.id == ticket.id { operation = nil; task = nil }
        }
        guard owns(ticket) else { return }
        do {
            switch ticket.kind {
            case .models:
                let values = try await store.service.models(draft)
                guard owns(ticket) else { return }
                models = values
                guard owns(ticket) else { models = []; return }
                modelsOpen = true
                if !owns(ticket) { models = []; modelsOpen = false }
            case .test:
                let value = try await store.service.test(draft)
                guard owns(ticket) else { return }
                testResult = value
                if !owns(ticket) { testResult = nil }
            case .save:
                let saved = await store.save(draft)
                guard owns(ticket) else { return }
                if saved {
                    scrubCredentials(includeProxy: false)
                    guard owns(ticket) else { return }
                    didSave = true
                    if !owns(ticket) { didSave = false }
                } else {
                    failure = store.failure
                    if !owns(ticket) { failure = nil }
                }
            }
        } catch {
            guard owns(ticket), !(error is CancellationError) else { return }
            failure = AppErrorMessage(error)
            if !owns(ticket) { failure = nil }
        }
    }
}
