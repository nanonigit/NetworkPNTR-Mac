import ArtexCore
import Foundation
import Observation

enum TaskBulkKind: Equatable { case control(TaskControlAction), move, delete }
struct TaskBulkContext: Identifiable { let id = UUID(); let kind: TaskBulkKind; let ids: [String] }
struct TaskBulkAcknowledgement: Identifiable { let id = UUID(); let ids: Set<String> }
struct TaskBulkItem: Identifiable {
    enum State: Equatable { case succeeded, rejected, unconfirmed, notStarted }
    let id: String
    let state: State
    var failure: AppErrorMessage?
    var queued = false
}
struct TaskBulkTotals {
    var assets = Decimal.zero, detached = Decimal.zero, traffic = Decimal.zero, findings = Decimal.zero, llm = Decimal.zero
    var filesDeleted = false
    var assetsText: String { NSDecimalNumber(decimal:assets).stringValue }
    mutating func add(_ row: TaskDeletionResult) {
        assets += Decimal(row.assetsDeleted); detached += Decimal(row.assetsDetached); traffic += Decimal(row.trafficDeleted)
        findings += Decimal(row.findingsDeleted); llm += Decimal(row.llmRecordsDeleted); filesDeleted = filesDeleted || row.filesDeleted
    }
}

@MainActor @Observable final class TaskBulkWorkspace {
    private(set) var viewOwner = UUID()
    private(set) var selectedIDs = Set<String>()
    private(set) var uncertainIDs = Set<String>()
    private(set) var context: TaskBulkContext?
    private(set) var acknowledgement: TaskBulkAcknowledgement?
    private(set) var options = TaskDeletionOptions()
    private(set) var targetID: Int64?
    private(set) var isMutating = false
    private(set) var hasSubmitted = false
    private(set) var items: [TaskBulkItem] = []
    private(set) var plannedIDs: [String] = []
    private(set) var totals = TaskBulkTotals()
    private(set) var warningIDs: [String] = []
    private(set) var failure: AppErrorMessage?
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let service: TaskService
    @ObservationIgnored private let categoryService: TaskCategoryService?
    @ObservationIgnored private let catalog: TaskCategoryWorkspace?
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var worker: Task<Bool,Never>?
    var completedCount: Int { items.filter{$0.state != .notStarted}.count }
    var queuedIDs: [String] { items.filter{$0.state == .succeeded && $0.queued}.map(\.id) }
    var categoryOptions: [TaskCategoryRecord] { catalog?.categories ?? [] }
    var canMove: Bool { categoryService != nil }
    init(store: TaskStore, service: TaskService, categoryService: TaskCategoryService? = nil, catalog: TaskCategoryWorkspace? = nil) {
        self.store = store; self.service = service; self.categoryService = categoryService; self.catalog = catalog
    }
    private var selectable: Bool { context == nil && !isMutating && acknowledgement == nil }
    func setSelected(_ id: String, selected: Bool, owner: UUID) {
        guard selectable, owner == viewOwner, store.list.value?.contains(where:{$0.id == id}) == true else { return }
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }
    func setAll(ids: [String], selected: Bool, owner: UUID) {
        for id in ids { setSelected(id,selected:selected,owner:owner) }
    }
    func clearSelection(owner: UUID) { guard selectable, viewOwner == owner else { return }; selectedIDs = [] }
    func reconcileSelection() {
        guard !isMutating, store.list.failure == nil, !store.list.isStale, let rows = store.list.value else { return }
        selectedIDs.formIntersection(Set(rows.map(\.id)))
    }
    func eligibleCount(_ action: TaskControlAction) -> Int {
        (store.list.value ?? []).filter { selectedIDs.contains($0.id) && TaskPresentation.controlAction($0.status) == action }.count
    }
    func begin(_ kind: TaskBulkKind) -> Bool {
        guard selectable, !store.isMutating else { return false }
        let rows = (store.list.value ?? []).filter { selectedIDs.contains($0.id) }
        let ids: [String]
        if case .control(let action) = kind { ids = rows.filter { TaskPresentation.controlAction($0.status) == action }.map(\.id) }
        else { ids = rows.map(\.id) }
        guard !ids.isEmpty else { return false }
        guard Set(ids).isDisjoint(with:uncertainIDs) else { failure = AppErrorMessage(key:.taskBulkUnknown); return false }
        if kind != .delete, ids.count > 100 { failure = AppErrorMessage(key:.taskBulkLimit); return false }
        guard kind != .move || categoryService != nil else { return false }
        context = .init(kind:kind,ids:ids); plannedIDs = ids; options = .init(); targetID = nil; hasSubmitted = false
        items = []; totals = .init(); warningIDs = []; failure = nil; return true
    }
    func setOption(_ key: WritableKeyPath<TaskDeletionOptions,Bool>, value: Bool, contextID: UUID) {
        guard context?.id == contextID, !isMutating, !hasSubmitted else { return }; options[keyPath:key] = value
    }
    func setTarget(_ id: Int64?, contextID: UUID) {
        guard context?.id == contextID, !isMutating, !hasSubmitted,
              id.map({ id in categoryOptions.contains(where:{$0.id == id}) }) ?? true else { return }
        targetID = id
    }
    func close(contextID: UUID) { guard context?.id == contextID, !isMutating else { return }; context = nil }
    func requestAcknowledgement() {
        guard selectable, !uncertainIDs.isEmpty else { return }; acknowledgement = .init(ids:uncertainIDs)
    }
    func resolveAcknowledgement(id: UUID, accept: Bool) {
        guard !isMutating, let choice = acknowledgement, choice.id == id else { return }
        acknowledgement = nil
        if accept { uncertainIDs.subtract(choice.ids); failure = nil }
    }
    func suspend() { worker?.cancel(); context = nil; acknowledgement = nil; viewOwner = UUID() }
    func reset() {
        suspend(); lifetime = UUID(); selectedIDs = []; uncertainIDs = []; items = []; plannedIDs = []
        totals = .init(); warningIDs = []; failure = nil; hasSubmitted = false; options = .init(); targetID = nil
    }
    func submit(contextID: UUID) async -> Bool {
        guard let work = start(contextID:contextID) else { return false }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
    func submitFromUI(contextID: UUID) { _ = start(contextID:contextID) }
    private func start(contextID: UUID) -> Task<Bool,Never>? {
        guard let captured = context, captured.id == contextID, !isMutating, !hasSubmitted, !Task.isCancelled else { return nil }
        if captured.kind == .move, let targetID, !categoryOptions.contains(where:{$0.id == targetID}) {
            failure = AppErrorMessage(key:.taskBulkTargetMissing); return nil
        }
        guard let token = store.beginBulkMutation() else { return nil }
        let life = lifetime, snapshotOptions = options, destination = targetID
        isMutating = true; hasSubmitted = true; failure = nil
        let work = Task { await self.execute(captured,token:token,life:life,options:snapshotOptions,target:destination) }
        worker = work; return work
    }
    private func execute(_ captured: TaskBulkContext, token: UUID, life: UUID, options: TaskDeletionOptions, target: Int64?) async -> Bool {
        defer { store.finishBulkMutation(ticket:token); isMutating = false; worker = nil }
        guard life == lifetime, !Task.isCancelled else { return false }
        switch captured.kind {
        case .delete:
            for id in captured.ids {
                guard life == lifetime, !Task.isCancelled else { break }
                do {
                    let result = try await service.delete(id:id,options:options)
                    guard life == lifetime else { return false }
                    store.applyBulkChange(ticket:token,change:.deleted(result)); totals.add(result); selectedIDs.remove(id)
                    if result.hasCleanupWarning { warningIDs.append(id) }
                    items.append(.init(id:id,state:.succeeded))
                } catch {
                    guard life == lifetime else { return false }
                    let state = classify(error); items.append(.init(id:id,state:state,failure:AppErrorMessage(error)))
                    if state == .unconfirmed { uncertainIDs.insert(id) }
                    if Task.isCancelled || isAuthenticationFailure(error) { break }
                }
            }
            guard life == lifetime else { return false }
            let attempted = Set(items.map(\.id)); items += captured.ids.filter { !attempted.contains($0) }.map { .init(id:$0,state:.notStarted) }
        case .control(let action):
            do {
                let result = try await service.controlBatch(ids:captured.ids,action:action)
                guard life == lifetime else { return false }
                store.applyBulkChange(ticket:token,change:.controlled(result))
                items = result.map { .init(id:$0.id,state:$0.ok ? .succeeded : .rejected,queued:$0.ok && $0.queued) }
            } catch { guard life == lifetime else { return false }; failedBatch(captured.ids,error:error) }
        case .move:
            do {
                guard let categoryService else { throw TaskInputError.invalidBatch }
                let result = try await categoryService.assignBatch(taskIDs:captured.ids,categoryID:target)
                guard life == lifetime else { return false }
                store.applyBulkChange(ticket:token,change:.moved(result))
                items = result.items.map { .init(id:$0.id,state:$0.ok ? .succeeded : .rejected) }
                if result.items.contains(where:{$0.ok}) { selectedIDs = [] }
            } catch { guard life == lifetime else { return false }; failedBatch(captured.ids,error:error) }
        }
        guard life == lifetime else { return false }
        catalog?.markStale(); store.finishBulkMutation(ticket:token)
        if context?.id == captured.id, !Task.isCancelled {
            await store.refreshList()
            if life == lifetime, context?.id == captured.id, !Task.isCancelled { await store.refreshSelected() }
        }
        return life == lifetime
    }
    private func failedBatch(_ ids: [String], error: any Error) {
        let state = classify(error); failure = AppErrorMessage(error)
        items = ids.map { .init(id:$0,state:state,failure:AppErrorMessage(error)) }
        if state == .unconfirmed { uncertainIDs.formUnion(ids) }
    }
    private func classify(_ error: any Error) -> TaskBulkItem.State {
        if error is TaskInputError || error is TaskCategoryInputError { return .rejected }
        if case let BackendAPIError.status(code) = error, [400,401,403,404,409,413,422].contains(code) { return .rejected }
        return .unconfirmed
    }
    private func isAuthenticationFailure(_ error: any Error) -> Bool {
        if case let BackendAPIError.status(code) = error { return code == 401 || code == 403 }; return false
    }
}
