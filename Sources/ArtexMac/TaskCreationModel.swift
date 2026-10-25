import ArtexCore
import Foundation
import Observation

struct TaskCreationContext: Identifiable { let id = UUID() }
struct TaskChoiceState<Value> {
    var value: [Value]?
    var failure: AppErrorMessage?
}

@MainActor @Observable final class TaskCreationModel {
    private(set) var context: TaskCreationContext?
    private(set) var form = TaskCreationForm()
    private(set) var selectedTemplateID: Int64?
    private(set) var categories = TaskChoiceState<TaskNamedOption>()
    private(set) var companies = TaskChoiceState<TaskNamedOption>()
    private(set) var profiles = TaskChoiceState<TaskProfileOption>()
    private(set) var templates = TaskChoiceState<TaskTemplateOption>()
    private(set) var sources = TaskChoiceState<TaskRecord>()
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var uncertain = false
    private(set) var failure: AppErrorMessage?
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let service: TaskCreationService
    @ObservationIgnored private var loadTicket = UUID()
    init(store: TaskStore, service: TaskCreationService) { self.store = store; self.service = service }
    func open() -> UUID? {
        guard context == nil, !isSubmitting else { return nil }
        let next = TaskCreationContext(); context = next
        if !uncertain { failure = nil }
        return next.id
    }
    func close(contextID: UUID) {
        guard context?.id == contextID, !isSubmitting else { return }
        context = nil; loadTicket = UUID(); isLoading = false
    }
    func discard(contextID: UUID) {
        guard context?.id == contextID, !isSubmitting else { return }
        close(contextID: contextID); form = .init(); selectedTemplateID = nil; uncertain = false; failure = nil
    }
    func reset() {
        context = nil; loadTicket = UUID(); isLoading = false
        form = .init(); selectedTemplateID = nil; uncertain = false; failure = nil
        categories = .init(); companies = .init(); profiles = .init(); templates = .init(); sources = .init()
    }
    private func editable(_ id: UUID) -> Bool { context?.id == id && !isSubmitting && !uncertain }
    func update<Value>(_ key: WritableKeyPath<TaskCreationForm, Value>, value: Value, contextID: UUID) {
        guard editable(contextID) else { return }; form[keyPath: key] = value
    }
    func toggle<Value: Equatable>(_ key: WritableKeyPath<TaskCreationForm, [Value]>, value: Value, maximum: Int, contextID: UUID) {
        guard editable(contextID) else { return }
        if let index = form[keyPath: key].firstIndex(of: value) { form[keyPath: key].remove(at: index) }
        else if form[keyPath: key].count < maximum { form[keyPath: key].append(value) }
    }
    func setSelected<Value: Equatable>(_ key: WritableKeyPath<TaskCreationForm, [Value]>, value: Value, selected: Bool, maximum: Int, contextID: UUID) {
        guard editable(contextID), form[keyPath: key].contains(value) != selected else { return }
        toggle(key, value: value, maximum: maximum, contextID: contextID)
    }
    func moveProfile(id: Int64, offset: Int, contextID: UUID) {
        guard editable(contextID), offset == 1 || offset == -1, let index = form.draft.llmProfileIds.firstIndex(of: id) else { return }
        let target = index + offset
        guard form.draft.llmProfileIds.indices.contains(target) else { return }
        form.draft.llmProfileIds.swapAt(index, target)
    }
    func chooseTemplate(_ id: Int64?, contextID: UUID) {
        guard editable(contextID) else { return }
        if let id {
            guard let template = templates.value?.first(where: { $0.id == id }) else { return }
            form.apply(template)
        }
        selectedTemplateID = id
    }
    func addRule(contextID: UUID) { guard editable(contextID) else { return }; form.rules.append(.init()) }
    func removeRule(id: UUID, contextID: UUID) { guard editable(contextID) else { return }; form.rules.removeAll { $0.id == id } }
    func updateRule<Value>(id: UUID, key: WritableKeyPath<TaskInterceptRuleDraft, Value>, value: Value, contextID: UUID) {
        guard editable(contextID), let index = form.rules.firstIndex(where: { $0.id == id }) else { return }
        form.rules[index].rule[keyPath: key] = value
    }
    func load(contextID: UUID) async {
        guard context?.id == contextID, !isLoading, !isSubmitting, !Task.isCancelled else { return }
        let ticket = UUID(); loadTicket = ticket; isLoading = true
        defer { if loadTicket == ticket { isLoading = false } }
        async let a: Void = loadCategories(ticket)
        async let b: Void = loadCompanies(ticket)
        async let c: Void = loadProfiles(ticket)
        async let d: Void = loadTemplates(ticket)
        async let e: Void = loadSources(ticket)
        _ = await (a,b,c,d,e)
    }
    private func fetch<Value: Sendable>(ticket: UUID, operation: () async throws -> [Value],
                                        apply: ([Value]?, AppErrorMessage?) -> Void) async {
        do {
            let value = try await operation()
            guard loadTicket == ticket, !Task.isCancelled else { return }
            apply(value, nil)
        } catch {
            guard loadTicket == ticket, !Task.isCancelled else { return }
            apply(nil, AppErrorMessage(error))
        }
    }
    private func loadCategories(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.categories() }) { value, error in
            if let value { self.categories.value = value }; self.categories.failure = error
        }
    }
    private func loadCompanies(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.companies() }) { value, error in
            if let value { self.companies.value = value }; self.companies.failure = error
        }
    }
    private func loadProfiles(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.profiles() }) { value, error in
            if let value { self.profiles.value = value }; self.profiles.failure = error
        }
    }
    private func loadTemplates(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.templates() }) { value, error in
            if let value { self.templates.value = value }; self.templates.failure = error
        }
    }
    private func loadSources(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.sources() }) { value, error in
            if let value { self.sources.value = value }; self.sources.failure = error
        }
    }
    private func validateChoices(_ draft: TaskCreateDraft) throws {
        func contains<T: Hashable>(_ selected: [T], _ available: [T]?) -> Bool { selected.isEmpty || available.map { Set(selected).isSubset(of: Set($0)) } == true }
        guard contains(draft.llmProfileIds, profiles.value?.map(\.id)), contains(draft.companyIds, companies.value?.map(\.id)),
              contains(draft.sourceTaskIds, sources.value?.map(\.id)), contains(draft.categoryId.map { [$0] } ?? [], categories.value?.map(\.id)) else { throw TaskInputError.invalidCreation }
    }
    func submit(contextID: UUID) async -> Bool {
        guard editable(contextID), !isLoading, !Task.isCancelled else { return false }
        let payload: TaskCreateDraft
        do { payload = try form.payload(); try validateChoices(payload) }
        catch { failure = AppErrorMessage(error); return false }
        isSubmitting = true; failure = nil
        defer { isSubmitting = false }
        let outcome = await store.create(payload)
        guard context?.id == contextID else { return false }
        switch outcome {
        case .confirmed:
            form = .init(); selectedTemplateID = nil; context = nil; failure = nil; uncertain = false; return true
        case .unconfirmed: uncertain = true; failure = store.mutationFailure; return false
        case .rejected: failure = store.mutationFailure; return false
        case .notStarted, .discarded: return false
        }
    }
}
