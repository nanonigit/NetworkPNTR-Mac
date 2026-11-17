import NetworkPNTRCore
import Foundation
import Observation

struct TaskTemplateForm {
    var name = ""
    var description = ""
    var goal = ""
    var categoryId: Int64?
    var rules: [TaskCreationRule] = []
    init(_ value: TaskTemplateDraft = .init()) {
        name = value.name; description = value.description; goal = value.goal; categoryId = value.categoryId
        rules = value.interceptRules.map { .init(rule: $0) }
    }
    var draft: TaskTemplateDraft {
        var value = TaskTemplateDraft(); value.name = name; value.description = description; value.goal = goal
        value.categoryId = categoryId; value.interceptRules = rules.map(\.rule); return value
    }
}
struct TaskTemplateContext: Identifiable { let id = UUID() }
struct TaskTemplateManagerDecision: Identifiable {
    enum Action { case replace(TaskTemplateDraft, Int64?), delete(TaskTemplateOption), localDiscard }
    let id = UUID()
    let editorID: UUID
    let action: Action
    var isDelete: Bool { if case .delete = action { return true }; return false }
    var isLocalDiscard: Bool { if case .localDiscard = action { return true }; return false }
    var name: String? { if case .delete(let value) = action { return value.name }; return nil }
}
enum TaskTemplateReceipt { case saved(TaskTemplateOption), deleted(Int64) }

@MainActor @Observable final class TaskTemplateManager {
    private(set) var context: TaskTemplateContext?
    private(set) var editorID = UUID()
    private(set) var form = TaskTemplateForm()
    private(set) var selectedID: Int64?
    private(set) var templates: [TaskTemplateOption] = []
    private(set) var categories: [TaskNamedOption] = []
    private(set) var pendingDecision: TaskTemplateManagerDecision?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var uncertain = false
    private(set) var failure: AppErrorMessage?
    private(set) var listFailure: AppErrorMessage?
    private(set) var categoryFailure: AppErrorMessage?
    private(set) var query = ""
    @ObservationIgnored var onReceipt: (@MainActor (TaskTemplateReceipt) -> Void)?
    @ObservationIgnored private let service: TaskTemplateService
    @ObservationIgnored private var baseline = TaskTemplateDraft()
    @ObservationIgnored private var initialized = false
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var readTicket = UUID()
    var isDirty: Bool { !form.draft.sameBytes(as: baseline) }
    init(service: TaskTemplateService) { self.service = service }
    func open(seed: TaskTemplateDraft?, templates initial: [TaskTemplateOption]) -> UUID? {
        guard context == nil, !isMutating else { return nil }
        context = .init()
        if !initialized {
            templates = initial; initialized = true
            if seed == nil, let first = initial.first { replace(TaskTemplateDraft(first), id: first.id) }
        }
        if !uncertain, var seed {
            seed.name = ""
            if isDirty { pendingDecision = .init(editorID: editorID, action: .replace(seed,nil)) }
            else { replace(seed,id:nil) }
        }
        return context?.id
    }
    func receiveCategories(_ rows: [TaskCategoryRecord]) {
        categories = rows.map { .init(id:$0.id,name:$0.name) }
    }
    func setQuery(_ value: String, contextID: UUID) { guard context?.id == contextID else { return }; query = value }
    func close(contextID: UUID) { guard context?.id == contextID, !isMutating else { return }; suspend() }
    func suspend() { context = nil; pendingDecision = nil; readTicket = UUID(); isLoading = false }
    func reset() {
        suspend(); lifetime = UUID(); replace(.init(),id:nil); templates = []; categories = []; initialized = false
        uncertain = false; failure = nil; listFailure = nil; categoryFailure = nil; query = ""
    }
    private func editable(_ contextID: UUID, _ editor: UUID) -> Bool {
        context?.id == contextID && editorID == editor && !isMutating && !uncertain && pendingDecision == nil
    }
    func update<Value>(_ key: WritableKeyPath<TaskTemplateForm,Value>, value: Value, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID) else { return }; form[keyPath:key] = value
    }
    func addRule(contextID: UUID, editorID: UUID) { guard editable(contextID,editorID) else { return }; form.rules.append(.init()) }
    func removeRule(id: UUID, contextID: UUID, editorID: UUID) { guard editable(contextID,editorID) else { return }; form.rules.removeAll { $0.id == id } }
    func updateRule<Value>(id: UUID, key: WritableKeyPath<TaskInterceptRuleDraft,Value>, value: Value, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), let index = form.rules.firstIndex(where: { $0.id == id }) else { return }
        form.rules[index].rule[keyPath:key] = value
    }
    func requestSelection(_ id: Int64?, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID) else { return }
        let value: TaskTemplateDraft
        if let id { guard let row = templates.first(where: { $0.id == id }) else { return }; value = TaskTemplateDraft(row) }
        else { value = .init() }
        if isDirty { pendingDecision = .init(editorID: editorID, action: .replace(value,id)) }
        else { replace(value,id:id) }
    }
    func requestDelete(contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), let id = selectedID, let row = templates.first(where: { $0.id == id }) else { return }
        pendingDecision = .init(editorID: editorID, action: .delete(row))
    }
    func requestLocalDiscard(contextID: UUID) {
        guard context?.id == contextID, uncertain, !isMutating, pendingDecision == nil else { return }
        pendingDecision = .init(editorID: editorID, action: .localDiscard)
    }
    @discardableResult func resolveDecision(id: UUID, confirm: Bool, contextID: UUID) async -> Bool {
        let resolution = resolveNow(id: id, confirm: confirm, contextID: contextID)
        if let worker = resolution.worker { return await worker.value }
        return resolution.completed
    }
    func resolveDecisionFromUI(id: UUID, confirm: Bool, contextID: UUID) { _ = resolveNow(id: id, confirm: confirm, contextID: contextID) }
    private func resolveNow(id: UUID, confirm: Bool, contextID: UUID) -> (completed: Bool, worker: Task<Bool,Never>?) {
        guard context?.id == contextID, !isMutating, let decision = pendingDecision,
              decision.id == id, decision.editorID == editorID else { return (false,nil) }
        pendingDecision = nil
        guard confirm else { return (false,nil) }
        switch decision.action {
        case let .replace(value,selected): replace(value,id:selected); return (true,nil)
        case .localDiscard: uncertain = false; failure = nil; replace(.init(),id:nil); return (true,nil)
        case let .delete(row):
            let life = lifetime
            isMutating = true; failure = nil; readTicket = UUID(); isLoading = false
            return (false,Task { await self.remove(row,life:life) })
        }
    }
    private func replace(_ value: TaskTemplateDraft, id: Int64?) {
        form = .init(value); selectedID = id; baseline = id == nil ? .init() : value; editorID = UUID()
    }
    func load(contextID: UUID) async {
        guard context?.id == contextID, !isMutating, !isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); readTicket = ticket; isLoading = true
        defer { if readTicket == ticket { isLoading = false } }
        async let a: Void = loadTemplates(ticket, contextID)
        async let b: Void = loadCategories(ticket, contextID)
        _ = await (a,b)
    }
    private func loadTemplates(_ ticket: UUID, _ contextID: UUID) async {
        do {
            let rows = try await service.list()
            guard readTicket == ticket, context?.id == contextID, !Task.isCancelled else { return }
            templates = rows; listFailure = nil
        } catch {
            guard readTicket == ticket, context?.id == contextID, !Task.isCancelled else { return }
            listFailure = AppErrorMessage(error)
        }
    }
    private func loadCategories(_ ticket: UUID, _ contextID: UUID) async {
        do {
            let rows = try await service.categories()
            guard readTicket == ticket, context?.id == contextID, !Task.isCancelled else { return }
            categories = rows; categoryFailure = nil
        } catch {
            guard readTicket == ticket, context?.id == contextID, !Task.isCancelled else { return }
            categoryFailure = AppErrorMessage(error)
        }
    }
    func save(contextID: UUID, editorID: UUID) async -> Bool {
        guard editable(contextID,editorID), !isLoading, !Task.isCancelled else { return false }
        let draft = form.draft
        do {
            _ = try draft.encoded()
            guard draft.categoryId.map({ id in categories.contains(where: { $0.id == id }) }) ?? true else { throw TaskTemplateInputError.invalid }
        } catch { failure = AppErrorMessage(error); return false }
        let life = lifetime, selected = selectedID
        isMutating = true; failure = nil; readTicket = UUID(); isLoading = false
        defer { isMutating = false }
        do {
            let value: TaskTemplateOption
            if let selected { value = try await service.update(id:selected,draft:draft) }
            else { value = try await service.create(draft) }
            guard life == lifetime else { return false }
            templates = [value] + templates.filter { $0.id != value.id }
            if self.editorID == editorID { replace(TaskTemplateDraft(value),id:value.id) }
            uncertain = false; onReceipt?(.saved(value)); return true
        } catch { guard life == lifetime else { return false }; mutationFailed(error); return false }
    }
    private func remove(_ row: TaskTemplateOption, life: UUID) async -> Bool {
        defer { isMutating = false }
        guard life == lifetime, !Task.isCancelled else { return false }
        do {
            let id = try await service.delete(id:row.id)
            guard life == lifetime else { return false }
            templates.removeAll { $0.id == id }
            if selectedID == id {
                if let next = templates.first { replace(TaskTemplateDraft(next),id:next.id) }
                else { replace(.init(),id:nil) }
            }
            uncertain = false; onReceipt?(.deleted(id)); return true
        } catch { guard life == lifetime else { return false }; mutationFailed(error); return false }
    }
    private func mutationFailed(_ error: any Error) {
        if case BackendAPIError.status(409) = error { failure = AppErrorMessage(key:.taskTemplateConflict) }
        else { failure = AppErrorMessage(error) }
        if error is TaskTemplateInputError { uncertain = false }
        else if case let BackendAPIError.status(code) = error, [400,401,403,404,409,413,422].contains(code) { uncertain = false }
        else { uncertain = true }
    }
}
