import Foundation
import Observation

public struct TaskReadState<Value: Sendable>: Sendable {
    public internal(set) var value: Value?
    public internal(set) var isLoading = false
    public internal(set) var isStale = true
    public internal(set) var failure: AppErrorMessage?
}

/// A transport failure after starting a mutation never proves that it was rolled back.
public enum TaskMutationOutcome<Value: Sendable>: Sendable {
    case notStarted, rejected, unconfirmed, discarded
    case confirmed(Value)
}

public enum TaskMutationConfirmation: Sendable {
    case created(TaskRecord), updated(TaskRecord), controlled(TaskControlResult)
    case batchControlled([TaskBatchControlItem]), deleted(TaskDeletionResult)
}

@MainActor @Observable public final class TaskStore {
    public private(set) var list = TaskReadState<[TaskRecord]>()
    public private(set) var detail = TaskReadState<TaskRecord>()
    public private(set) var activeID: String?
    public private(set) var selectedID: String?
    public private(set) var lastConfirmation: TaskMutationConfirmation?
    public private(set) var mutationFailure: AppErrorMessage?
    public private(set) var mutationUncertain = false
    public private(set) var isMutating = false
    public private(set) var isPolling = false
    @ObservationIgnored private let service: TaskService
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var externalTicket: (id: UUID, life: UUID, kind: ExternalKind)?
    private enum ExternalKind { case category, bulk }
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var activity = UUID()
    @ObservationIgnored private var listTicket = UUID()
    @ObservationIgnored private var detailTicket = UUID()
    @ObservationIgnored private var pollTicket: UUID?

    public init(service: TaskService, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service; self.sleep = sleep
    }

    public func refreshList() async {
        guard !isMutating, !list.isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); listTicket = ticket; list.isLoading = true
        defer { if listTicket == ticket { list.isLoading = false } }
        do {
            let snapshot = try await service.list()
            guard listTicket == ticket, !Task.isCancelled else { return }
            list.value = snapshot.tasks; activeID = snapshot.activeID
            list.failure = nil; list.isStale = false
        } catch {
            guard listTicket == ticket, !Task.isCancelled else { return }
            list.failure = AppErrorMessage(error); list.isStale = true
        }
    }

    /// Local navigation only: reading detail does not activate or launch a task.
    public func select(id: String?) async {
        guard !Task.isCancelled else { return }
        let next: String?
        do { next = try id.map(TaskWire.canonicalID) }
        catch { detail.failure = AppErrorMessage(error); return }
        if next != selectedID {
            selectedID = next; detailTicket = UUID(); detail = .init()
        }
        if next != nil { await refreshSelected() }
    }

    public func refreshSelected() async {
        guard let id = selectedID, !isMutating, !detail.isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); detailTicket = ticket; detail.isLoading = true
        defer { if detailTicket == ticket { detail.isLoading = false } }
        do {
            let task = try await service.detail(id: id)
            guard detailTicket == ticket, selectedID == id, !Task.isCancelled else { return }
            detail.value = task; detail.failure = nil; detail.isStale = false
        } catch {
            guard detailTicket == ticket, selectedID == id, !Task.isCancelled else { return }
            detail.failure = AppErrorMessage(error); detail.isStale = true
        }
    }

    public func beginCategoryMutation() -> UUID? {
        beginExternalMutation(kind:.category)
    }
    private func beginExternalMutation(kind: ExternalKind) -> UUID? {
        guard !isMutating, !Task.isCancelled else { return nil }
        let id = UUID(); externalTicket = (id,lifetime,kind); isMutating = true; invalidateReads()
        mutationFailure = nil; mutationUncertain = false; lastConfirmation = nil
        return id
    }
    public func finishCategoryMutation(ticket: UUID, change: TaskCategoryChange?) {
        guard let owner = externalTicket, owner.id == ticket, owner.kind == .category else { return }
        externalTicket = nil; isMutating = false; invalidateReads()
        guard owner.life == lifetime else { return }
        if let change {
            if let tasks = list.value { list.value = change.applying(to:tasks) }
            if let task = detail.value { detail.value = change.applying(to:[task]).first }
        }
        list.isStale = true; detail.isStale = true
    }

    public func beginBulkMutation() -> UUID? { beginExternalMutation(kind:.bulk) }
    @discardableResult public func applyBulkChange(ticket: UUID, change: TaskBulkChange) -> Bool {
        guard let owner = externalTicket, owner.id == ticket, owner.kind == .bulk, owner.life == lifetime else { return false }
        invalidateReads(); list.isStale = true; detail.isStale = true
        switch change {
        case .deleted(let result):
            list.value?.removeAll { $0.id == result.deleted }
            if activeID == result.deleted { activeID = nil }
            if selectedID == result.deleted { selectedID = nil; detail = .init() }
        case .controlled(let items):
            func project(_ original: TaskRecord) -> TaskRecord {
                var row = original
                if let item = items.first(where:{$0.id == row.id && $0.ok}), let status = item.status {
                    row.status = status; row.paused = status == "paused"; row.queued = item.queued
                }
                return row
            }
            list.value = list.value?.map(project); detail.value = detail.value.map(project)
        case .moved(let result):
            let change = TaskCategoryChange.batchAssigned(result)
            if let rows = list.value { list.value = change.applying(to:rows) }
            if let row = detail.value { detail.value = change.applying(to:[row]).first }
        }
        return true
    }
    public func finishBulkMutation(ticket: UUID) {
        guard let owner = externalTicket, owner.id == ticket, owner.kind == .bulk else { return }
        externalTicket = nil; isMutating = false; invalidateReads()
        guard owner.life == lifetime else { return }
        list.isStale = true; detail.isStale = true
    }

    public func create(_ draft: TaskCreateDraft) async -> TaskMutationOutcome<TaskRecord> {
        await perform(confirm: TaskMutationConfirmation.created) { try await self.service.create(draft) }
    }
    public func update(id: String, patch: TaskMetadataPatch) async -> TaskMutationOutcome<TaskRecord> {
        await perform(confirm: TaskMutationConfirmation.updated) { try await self.service.update(id: id, patch: patch) }
    }
    public func control(id: String, action: TaskControlAction) async -> TaskMutationOutcome<TaskControlResult> {
        await perform(confirm: TaskMutationConfirmation.controlled) { try await self.service.control(id: id, action: action) }
    }
    public func controlBatch(ids: [String], action: TaskControlAction) async -> TaskMutationOutcome<[TaskBatchControlItem]> {
        await perform(confirm: TaskMutationConfirmation.batchControlled) { try await self.service.controlBatch(ids: ids, action: action) }
    }
    public func delete(id: String, options: TaskDeletionOptions = .init()) async -> TaskMutationOutcome<TaskDeletionResult> {
        await perform(confirm: TaskMutationConfirmation.deleted) { try await self.service.delete(id: id, options: options) }
    }

    private func perform<Value: Sendable>(confirm: (Value) -> TaskMutationConfirmation,
                                         operation: () async throws -> Value) async -> TaskMutationOutcome<Value> {
        guard !isMutating, !Task.isCancelled else { return .notStarted }
        let life = lifetime; let visible = activity
        isMutating = true; invalidateReads()
        mutationFailure = nil; mutationUncertain = false; lastConfirmation = nil
        do {
            let value = try await operation()
            // Reset cannot release the gate while a previous-session operation is pending.
            isMutating = false
            guard life == lifetime else { return .discarded }
            let receipt = confirm(value); lastConfirmation = receipt
            list.isStale = true; detail.isStale = true
            if case .deleted(let result) = receipt {
                list.value?.removeAll { $0.id == result.deleted }
                if activeID == result.deleted { activeID = nil }
                if selectedID == result.deleted { selectedID = nil; detail = .init(); detailTicket = UUID() }
            }
            // Refresh errors belong to read state and cannot erase a confirmed mutation.
            if visible == activity, !Task.isCancelled {
                await refreshList()
                if visible == activity, life == lifetime { await refreshSelected() }
            }
            return life == lifetime ? .confirmed(value) : .discarded
        } catch {
            isMutating = false
            guard life == lifetime else { return .discarded }
            mutationFailure = AppErrorMessage(error)
            if error is TaskInputError { return .rejected }
            mutationUncertain = true; list.isStale = true; detail.isStale = true
            return .unconfirmed
        }
    }

    private func invalidateReads() {
        listTicket = UUID(); detailTicket = UUID()
        list.isLoading = false; detail.isLoading = false
    }

    public func stop() {
        activity = UUID(); pollTicket = nil; isPolling = false
        invalidateReads()
    }

    /// Call at authenticated-session teardown. Pending mutation results belong to the old lifetime.
    public func reset() {
        stop(); lifetime = UUID()
        list = .init(); detail = .init(); selectedID = nil; activeID = nil
        lastConfirmation = nil; mutationFailure = nil; mutationUncertain = false
    }

    public func run() async {
        guard pollTicket == nil, !Task.isCancelled else { return }
        let ticket = UUID(); pollTicket = ticket; isPolling = true
        defer { if pollTicket == ticket { pollTicket = nil; isPolling = false } }
        while pollTicket == ticket, !Task.isCancelled {
            await refreshList()
            guard pollTicket == ticket, !Task.isCancelled else { return }
            await refreshSelected()
            guard pollTicket == ticket, !Task.isCancelled else { return }
            do { try await sleep(.seconds(10)) } catch { return }
        }
    }
}
