import ArtexCore
import Foundation
import Observation

enum TaskCategorySelection: Hashable { case new, uncategorized, category(Int64) }
struct TaskCategoryContext: Identifiable { let id = UUID(); let inlineOwner: UUID? }
struct TaskCategoryDecision: Identifiable {
    enum Action {
        case select(TaskCategorySelection,String), delete(TaskCategoryRecord), move([String],Int64?), discard
    }
    let id = UUID()
    let editorID: UUID
    let action: Action
    var targetName: String? = nil
    var taskIDs: [String] { if case .move(let ids,_) = action { return ids }; return [] }
    var deleteCount: Int64 { if case .delete(let row) = action { return row.taskCount }; return 0 }
    var isDelete: Bool { if case .delete = action { return true }; return false }
    var isMove: Bool { if case .move = action { return true }; return false }
    var isDiscard: Bool { if case .discard = action { return true }; return false }
    var name: String? { if case .delete(let row) = action { return row.name }; return nil }
}

@MainActor @Observable final class TaskCategoryWorkspace {
    private(set) var context: TaskCategoryContext?
    private(set) var editorID = UUID()
    private(set) var selection: TaskCategorySelection = .new
    private(set) var name = ""
    private(set) var categories: [TaskCategoryRecord] = []
    private(set) var tasks: [TaskRecord] = []
    private(set) var selectedTaskIDs = Set<String>()
    private(set) var decision: TaskCategoryDecision?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var uncertain = false
    private(set) var countsStale = true
    private(set) var failure: AppErrorMessage?
    private(set) var categoryFailure: AppErrorMessage?
    private(set) var taskFailure: AppErrorMessage?
    private(set) var lastChange: TaskCategoryChange?
    @ObservationIgnored var onCatalog: (@MainActor ([TaskCategoryRecord]) -> Void)?
    @ObservationIgnored var onChange: (@MainActor (TaskCategoryChange,UUID?) -> Void)?
    @ObservationIgnored private let service: TaskCategoryService
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private var baseline = ""
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var readTicket = UUID()
    @ObservationIgnored private var initialized = false
    var isDirty: Bool { !name.utf8.elementsEqual(baseline.utf8) }
    var visibleTasks: [TaskRecord] {
        tasks.filter { task in switch selection { case .new: false; case .uncategorized: task.categoryId == nil; case .category(let id): task.categoryId == id } }
    }
    init(service: TaskCategoryService, store: TaskStore) { self.service = service; self.store = store }
    func open(tasks initial: [TaskRecord], inlineOwner: UUID? = nil, seedName: String = "") -> UUID? {
        guard context == nil, !isMutating else { return nil }
        invalidateReads(); context = .init(inlineOwner:inlineOwner)
        if !initialized { tasks = initial }
        if inlineOwner != nil, !uncertain {
            if isDirty { decision = .init(editorID:editorID,action:.select(.new,seedName)) }
            else { replace(.new,name:seedName) }
        }
        return context?.id
    }
    func close(contextID: UUID) { guard context?.id == contextID, !isMutating, decision == nil else { return }; suspend() }
    func suspend() { context = nil; decision = nil; invalidateReads() }
    func reset() {
        suspend(); lifetime = UUID(); categories = []; tasks = []; replace(.new,name:""); initialized = false
        uncertain = false; failure = nil; categoryFailure = nil; taskFailure = nil; lastChange = nil; countsStale = true
    }
    private func invalidateReads() { readTicket = UUID(); isLoading = false }
    private func editable(_ owner: UUID, _ editor: UUID) -> Bool {
        context?.id == owner && editorID == editor && !isMutating && !uncertain && decision == nil
    }
    func setName(_ value: String, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), selection != .uncategorized else { return }; name = value
    }
    private func replace(_ value: TaskCategorySelection, name: String) {
        selection = value; self.name = name; baseline = value == .new ? "" : name
        editorID = UUID(); selectedTaskIDs = []
    }
    func select(_ value: TaskCategorySelection, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), context?.inlineOwner == nil else { return }
        let nextName: String
        if case .category(let id) = value { guard let row = categories.first(where:{$0.id == id}) else { return }; nextName = row.name }
        else { nextName = "" }
        if isDirty { decision = .init(editorID:editorID,action:.select(value,nextName)) }
        else { replace(value,name:nextName) }
    }
    func selectTask(_ id: String, selected: Bool, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), visibleTasks.contains(where:{$0.id == id}) else { return }
        if selected { selectedTaskIDs.insert(id) } else { selectedTaskIDs.remove(id) }
    }
    func requestDelete(contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), case .category(let id) = selection, let row = categories.first(where:{$0.id == id}) else { return }
        decision = .init(editorID:editorID,action:.delete(row))
    }
    func requestMove(ids: [String], target: Int64?, contextID: UUID, editorID: UUID) {
        guard editable(contextID,editorID), !ids.isEmpty, Set(ids).count == ids.count, ids.count <= 100,
              target.map({ id in categories.contains(where:{$0.id == id}) }) ?? true,
              ids.allSatisfy({ id in tasks.contains(where:{$0.id == id}) }),
              ids.contains(where: { id in tasks.contains(where:{$0.id == id && $0.categoryId != target}) }) else { return }
        decision = .init(editorID:editorID,action:.move(ids,target),targetName:target.flatMap { id in categories.first(where:{$0.id == id})?.name })
    }
    func requestDiscard(contextID: UUID) {
        guard context?.id == contextID, uncertain, !isMutating, decision == nil else { return }
        decision = .init(editorID:editorID,action:.discard)
    }
    @discardableResult func resolve(id: UUID, accept: Bool, contextID: UUID) async -> Bool {
        let result = resolveNow(id:id,accept:accept,contextID:contextID)
        return await result.worker?.value ?? result.done
    }
    func resolveFromUI(id: UUID, accept: Bool, contextID: UUID) { _ = resolveNow(id:id,accept:accept,contextID:contextID) }
    private func resolveNow(id: UUID, accept: Bool, contextID: UUID) -> (done: Bool,worker: Task<Bool,Never>?) {
        guard context?.id == contextID, !isMutating, let choice = decision, choice.id == id, choice.editorID == editorID else { return (false,nil) }
        decision = nil; guard accept else { return (false,nil) }
        switch choice.action {
        case .select(let value,let name): replace(value,name:name); return (true,nil)
        case .discard: uncertain = false; failure = nil; replace(.new,name:""); return (true,nil)
        case .delete, .move:
            guard let token = claim() else { return (false,nil) }
            let life = lifetime, inline = context?.inlineOwner
            return (false,Task { await self.execute(choice.action,token:token,life:life,inline:inline) })
        }
    }
    private func claim() -> UUID? {
        guard !isMutating, !Task.isCancelled, let token = store.beginCategoryMutation() else { return nil }
        isMutating = true; invalidateReads(); failure = nil; lastChange = nil; return token
    }
    func save(contextID: UUID, editorID: UUID) async -> Bool {
        guard editable(contextID,editorID), !isLoading, selection != .uncategorized, let token = claim() else { return false }
        let life = lifetime, inline = context?.inlineOwner, selection = selection, name = name
        return await finish(token:token,life:life,inline:inline) {
            let row: TaskCategoryRecord
            if case .category(let id) = selection { row = try await self.service.rename(id:id,name:name) }
            else { row = try await self.service.create(name:name) }
            return .saved(row)
        }
    }
    private func execute(_ action: TaskCategoryDecision.Action, token: UUID, life: UUID, inline: UUID?) async -> Bool {
        await finish(token:token,life:life,inline:inline) {
            switch action {
            case .delete(let row): return .deleted(try await self.service.delete(id:row.id))
            case .move(let ids,let target):
                if ids.count == 1 { return .assigned(try await self.service.assign(taskID:ids[0],categoryID:target)) }
                return .batchAssigned(try await self.service.assignBatch(taskIDs:ids,categoryID:target))
            default: throw TaskCategoryInputError.invalid
            }
        }
    }
    private func finish(token: UUID, life: UUID, inline: UUID?, operation: () async throws -> TaskCategoryChange) async -> Bool {
        var receipt: TaskCategoryChange?
        defer { store.finishCategoryMutation(ticket:token,change:receipt); isMutating = false }
        guard life == lifetime, !Task.isCancelled else { return false }
        do {
            let change = try await operation(); guard life == lifetime else { return false }
            receipt = change; lastChange = change; uncertain = false; countsStale = true
            tasks = change.applying(to:tasks)
            switch change {
            case .saved(let row):
                categories = [row] + categories.filter { $0.id != row.id }; replace(.category(row.id),name:row.name)
            case .deleted(let id):
                categories.removeAll { $0.id == id }
                if let row = categories.first { replace(.category(row.id),name:row.name) } else { replace(.uncategorized,name:"") }
            case .assigned: selectedTaskIDs = []
            case .batchAssigned(let result): selectedTaskIDs.subtract(result.items.filter(\.ok).map(\.id))
            }
            onCatalog?(categories); onChange?(change,inline)
            if inline != nil { context = nil }
            return true
        } catch {
            guard life == lifetime else { return false }
            failure = AppErrorMessage(error)
            if error is TaskCategoryInputError || error is TaskInputError { uncertain = false }
            else if case let BackendAPIError.status(code) = error, [400,401,403,404,409,413,422].contains(code) { uncertain = false }
            else { uncertain = true }
            return false
        }
    }
    func refreshCatalog() async {
        guard context == nil, !isMutating, !isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); readTicket = ticket; isLoading = true
        defer { if readTicket == ticket { isLoading = false } }
        do {
            let values = try await service.list()
            guard readTicket == ticket, context == nil, !Task.isCancelled else { return }
            categories = values; categoryFailure = nil; countsStale = false; onCatalog?(values)
        } catch { guard readTicket == ticket, context == nil, !Task.isCancelled else { return }; categoryFailure = AppErrorMessage(error) }
    }
    func load(contextID: UUID) async {
        guard context?.id == contextID, !isMutating, !isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); readTicket = ticket; isLoading = true
        defer { if readTicket == ticket { isLoading = false } }
        async let a: Void = loadCategories(ticket:ticket,owner:contextID)
        async let b: Void = loadTasks(ticket:ticket,owner:contextID)
        _ = await (a,b)
    }
    private func loadCategories(ticket: UUID, owner: UUID) async {
        do {
            let values = try await service.list()
            guard readTicket == ticket, context?.id == owner, !Task.isCancelled else { return }
            categories = values; categoryFailure = nil; countsStale = false
            if !initialized, context?.inlineOwner == nil, !isDirty, decision == nil {
                if let row = values.first { replace(.category(row.id),name:row.name) }
                else { replace(.uncategorized,name:"") }
            }
            initialized = true; onCatalog?(categories)
        } catch { guard readTicket == ticket, context?.id == owner, !Task.isCancelled else { return }; categoryFailure = AppErrorMessage(error); countsStale = true }
    }
    private func loadTasks(ticket: UUID, owner: UUID) async {
        do {
            let values = try await service.tasks()
            guard readTicket == ticket, context?.id == owner, !Task.isCancelled else { return }
            tasks = values; selectedTaskIDs.formIntersection(Set(values.map(\.id))); taskFailure = nil
        } catch { guard readTicket == ticket, context?.id == owner, !Task.isCancelled else { return }; taskFailure = AppErrorMessage(error) }
    }
}
