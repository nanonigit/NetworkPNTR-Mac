import NetworkPNTRCore
import Foundation
import Observation

enum TaskArchiveActionKind: Equatable { case archive, restore, delete, retry }
struct TaskArchiveActionContext: Identifiable {
    let id = UUID()
    let kind: TaskArchiveActionKind
    let tasks: [TaskRecord]
    let archives: [TaskArchiveRecord]
    let batch: Bool
    var taskIDs: [String] { tasks.isEmpty ? archives.map{String($0.taskId)} : tasks.map(\.id) }
    var archiveIDs: [Int64] { archives.map(\.id) }
    var resultIDs: [String] { kind == .archive ? taskIDs : archiveIDs.map(String.init) }
}
struct TaskArchiveActionItem: Identifiable {
    enum State: Equatable { case accepted, rejected, unconfirmed, notStarted }
    let id: String
    let state: State
    var archiveID: Int64?
    var failure: AppErrorMessage?
}
struct TaskArchiveAcknowledgement: Identifiable {
    let id = UUID()
    let taskIDs: Set<String>
    let archiveIDs: Set<Int64>
}

/// Captures explicit actions; queue acceptance never projects archive or task completion.
@MainActor @Observable final class TaskArchiveWorkspace {
    private(set) var context: TaskArchiveActionContext?
    private(set) var acknowledgement: TaskArchiveAcknowledgement?
    private(set) var items: [TaskArchiveActionItem] = []
    private(set) var failure: AppErrorMessage?
    private(set) var uncertainTaskIDs = Set<String>()
    private(set) var uncertainArchiveIDs = Set<Int64>()
    private(set) var isSubmitting = false
    private(set) var hasSubmitted = false
    private(set) var receiptRevision = UUID()
    private(set) var lastReceiptKind: TaskArchiveActionKind?
    @ObservationIgnored var onReceipt: (@MainActor (TaskArchiveActionContext) -> Void)?
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let archives: TaskArchiveStore
    @ObservationIgnored private let service: TaskArchiveService
    @ObservationIgnored private var lifetime = UUID()
    @ObservationIgnored private var worker: Task<Bool,Never>?
    private var available: Bool { context == nil && acknowledgement == nil && !isSubmitting && !store.isMutating && !archives.isMutating }
    init(store: TaskStore, archives: TaskArchiveStore, service: TaskArchiveService) { self.store = store; self.archives = archives; self.service = service }

    func beginArchive(_ tasks: [TaskRecord], batch: Bool) -> Bool {
        guard available, batch || tasks.count == 1 else { return false }
        var seen = Set<String>()
        let rows = tasks.filter { TaskArchiveSemantics.canArchive($0,batch:batch) && seen.insert($0.id).inserted }
        guard !rows.isEmpty, rows.count <= 100 else { return reject(TaskArchiveInputError.batch) }
        return install(.init(kind:.archive,tasks:rows,archives:[],batch:batch))
    }
    func begin(_ kind: TaskArchiveActionKind, archives rows: [TaskArchiveRecord]) -> Bool {
        guard available, kind != .archive else { return false }
        guard !rows.isEmpty, rows.count <= 100, kind != .retry || rows.count == 1 else { return reject(TaskArchiveInputError.batch) }
        var seen = Set<Int64>()
        let eligible = rows.filter { row in
            let allowed: Bool
            switch kind { case .restore: allowed = TaskArchiveSemantics.canRestore(row); case .delete: allowed = TaskArchiveSemantics.canDelete(row); case .retry: allowed = TaskArchiveSemantics.canRetry(row); case .archive: allowed = false }
            return allowed && seen.insert(row.id).inserted
        }
        guard !eligible.isEmpty else { return reject(TaskArchiveInputError.action) }
        return install(.init(kind:kind,tasks:[],archives:eligible,batch:eligible.count > 1))
    }
    private func install(_ next: TaskArchiveActionContext) -> Bool {
        guard Set(next.taskIDs).isDisjoint(with:uncertainTaskIDs), Set(next.archiveIDs).isDisjoint(with:uncertainArchiveIDs) else {
            failure = .init(key:.taskBulkUnknown); return false
        }
        context = next; items = []; failure = nil; hasSubmitted = false; return true
    }
    private func reject(_ error: TaskArchiveInputError) -> Bool { failure = .init(error); return false }
    func close(contextID: UUID) { guard context?.id == contextID, !isSubmitting else { return }; context = nil }
    func requestAcknowledgement() {
        guard available, !uncertainTaskIDs.isEmpty || !uncertainArchiveIDs.isEmpty else { return }
        acknowledgement = .init(taskIDs:uncertainTaskIDs,archiveIDs:uncertainArchiveIDs)
    }
    func resolveAcknowledgement(id: UUID, accept: Bool) {
        guard !isSubmitting, let captured = acknowledgement, captured.id == id else { return }
        acknowledgement = nil
        if accept { uncertainTaskIDs.subtract(captured.taskIDs); uncertainArchiveIDs.subtract(captured.archiveIDs); failure = nil }
    }
    func cancel(contextID: UUID) { guard context?.id == contextID, isSubmitting else { return }; worker?.cancel() }
    func suspend() { worker?.cancel(); context = nil; acknowledgement = nil }
    func reset() {
        suspend(); lifetime = UUID(); items = []; failure = nil; uncertainTaskIDs = []; uncertainArchiveIDs = []
        hasSubmitted = false; receiptRevision = UUID(); lastReceiptKind = nil
    }
    func submitFromUI(contextID: UUID) { _ = start(contextID:contextID) }
    func submit(contextID: UUID) async -> Bool {
        guard let work = start(contextID:contextID) else { return false }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
    private func start(contextID: UUID) -> Task<Bool,Never>? {
        guard let captured = context, captured.id == contextID, !isSubmitting, !hasSubmitted, !Task.isCancelled,
              let liveToken = store.beginArchiveMutation() else { return nil }
        guard let coldToken = archives.beginMutation() else { store.finishArchiveMutation(ticket:liveToken); return nil }
        let life = lifetime, session = archives.sessionOwner
        isSubmitting = true; hasSubmitted = true; failure = nil
        let operation = Task { await self.execute(captured,life:life,session:session,liveToken:liveToken,coldToken:coldToken) }
        worker = operation; return operation
    }
    private func execute(_ captured: TaskArchiveActionContext, life: UUID, session: UUID, liveToken: UUID, coldToken: UUID) async -> Bool {
        var validReceipt = false
        defer {
            archives.finishMutation(ticket:coldToken,clearSelection:validReceipt)
            store.finishArchiveMutation(ticket:liveToken); isSubmitting = false; worker = nil
        }
        guard life == lifetime else { return false }
        guard !Task.isCancelled else {
            items = captured.resultIDs.map{.init(id:$0,state:.notStarted)}; return false
        }
        let handoff = TaskRequestHandoff {
            guard life == self.lifetime, self.context?.id == captured.id else { throw CancellationError() }
            try self.store.checkExternalMutation(ticket:liveToken)
            try self.archives.checkMutation(ticket:coldToken)
        }
        do {
            if captured.batch {
                let result: [TaskArchiveBatchItem]
                switch captured.kind {
                case .archive: result = try await service.queueBatch(taskIDs:captured.taskIDs,handoff:handoff)
                case .restore: result = try await service.restoreBatch(ids:captured.archiveIDs,handoff:handoff)
                case .delete: result = try await service.deleteBatch(ids:captured.archiveIDs,handoff:handoff)
                case .retry: throw TaskArchiveInputError.action
                }
                guard life == lifetime else { return false }
                items = result.map{.init(id:$0.id,state:$0.ok ? .accepted : .rejected,archiveID:$0.archiveId)}
                if captured.kind == .restore {
                    for item in result where item.ok {
                        guard let row = captured.archives.first(where:{String($0.id) == item.id}) else { throw BackendAPIError.invalidResponse }
                        _ = archives.observeAcceptedRestore(item,taskID:row.taskId,owner:session)
                    }
                }
            } else {
                let row: TaskArchiveRecord
                switch captured.kind {
                case .archive: row = try await service.queue(taskID:captured.taskIDs[0],handoff:handoff)
                case .restore: row = try await service.restore(id:captured.archiveIDs[0],handoff:handoff)
                case .delete: row = try await service.delete(id:captured.archiveIDs[0],handoff:handoff)
                case .retry: row = try await service.retry(captured.archives[0],handoff:handoff)
                }
                guard life == lifetime else { return false }
                guard String(row.taskId) == captured.taskIDs[0] else { throw BackendAPIError.invalidResponse }
                items = [.init(id:captured.resultIDs[0],state:.accepted,archiveID:row.id)]
                if row.state == "restore_queued" { _ = archives.observeAcceptedRestore(row,owner:session) }
            }
            validReceipt = true; lastReceiptKind = captured.kind; receiptRevision = UUID(); onReceipt?(captured)
        } catch {
            guard life == lifetime else { return false }
            if !handoff.wasDispatched {
                let state: TaskArchiveActionItem.State = error is CancellationError ? .notStarted : .rejected
                failure = error is CancellationError ? nil : AppErrorMessage(error)
                items = captured.resultIDs.map{.init(id:$0,state:state,failure:failure)}; return false
            }
            let state = classification(error); failure = AppErrorMessage(error)
            items = captured.resultIDs.map{.init(id:$0,state:state,failure:AppErrorMessage(error))}
            if state == .unconfirmed { uncertainTaskIDs.formUnion(captured.taskIDs); uncertainArchiveIDs.formUnion(captured.archiveIDs) }
        }
        return life == lifetime
    }
    private func classification(_ error: any Error) -> TaskArchiveActionItem.State {
        if error is TaskArchiveInputError || error is TaskInputError { return .rejected }
        if case let BackendAPIError.status(code) = error, [400,401,403,404,409,413,422].contains(code) { return .rejected }
        return .unconfirmed
    }
}
