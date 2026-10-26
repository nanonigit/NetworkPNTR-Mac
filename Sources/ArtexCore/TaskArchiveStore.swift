import Foundation
import Observation

/// Read ownership and accepted-restore reconciliation, separate from mutation dispatch.
@MainActor @Observable public final class TaskArchiveStore {
    public private(set) var list = TaskReadState<TaskArchivePage>()
    public private(set) var detail = TaskReadState<TaskArchiveRecord>()
    public private(set) var page: Int64 = 1
    public private(set) var size = 20
    public private(set) var query = ""
    public private(set) var state: String?
    public private(set) var selectedID: Int64?
    public private(set) var selectedIDs = Set<Int64>()
    public private(set) var viewOwner = UUID()
    public private(set) var sessionOwner = UUID()
    public private(set) var reconciliationRevision = UUID()
    public private(set) var removedAfterRestoreIDs = Set<Int64>()
    public private(set) var reconciliationFailure: AppErrorMessage?
    public private(set) var isRefreshing = false
    public private(set) var isPolling = false
    public var pendingRestoreIDs: Set<Int64> { Set(pending.keys) }
    @ObservationIgnored private let service: TaskArchiveService
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    private struct Pending: Sendable { let taskID: Int64; let token = UUID() }
    private var pending: [Int64:Pending] = [:]
    @ObservationIgnored private var readTicket = UUID()
    @ObservationIgnored private var detailTicket = UUID()
    @ObservationIgnored private var pollTicket: UUID?

    public init(service: TaskArchiveService, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for:$0) }) {
        self.service = service; self.sleep = sleep
    }
    /// The caller explicitly chooses the page; search/state UI changes should pass page1.
    @discardableResult public func configure(page: Int64, size: Int, query: String, state: String?) -> Bool {
        guard page > 0, (1...100).contains(size), page-1 <= Int64.max/Int64(size), query.utf8.count <= 4096, (state?.utf8.count ?? 0) <= 128 else { return false }
        let nextState = state == "" ? nil : state
        guard self.page != page || self.size != size || !self.query.utf8.elementsEqual(query.utf8) || !sameBytes(self.state,nextState) else { return true }
        invalidateReads(); self.page = page; self.size = size; self.query = query; self.state = nextState
        viewOwner = UUID(); list = .init(); detail = .init(); selectedID = nil; selectedIDs = []
        return true
    }
    public func setSelected(_ id: Int64, selected: Bool, owner: UUID) {
        guard owner == viewOwner, let row = list.value?.items.first(where:{$0.id == id}), !TaskArchiveSemantics.processing(row.state) else { return }
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }
    public func setAll(selected: Bool, owner: UUID) {
        for row in list.value?.items ?? [] { setSelected(row.id,selected:selected,owner:owner) }
    }
    public func select(_ id: Int64?) async {
        guard !Task.isCancelled, id.map({$0 > 0}) ?? true else { return }
        if selectedID != id { selectedID = id; detailTicket = UUID(); detail = .init() }
        await refreshSelected()
    }
    public func refreshSelected() async {
        guard let id = selectedID, !detail.isLoading, !Task.isCancelled else { return }
        let ticket = UUID(); detailTicket = ticket; detail.isLoading = true
        defer { if detailTicket == ticket { detail.isLoading = false } }
        do {
            let row = try await service.detail(id:id)
            guard detailTicket == ticket, selectedID == id, !Task.isCancelled else { return }
            detail.value = row; detail.isStale = false; detail.failure = nil
        } catch {
            guard detailTicket == ticket, selectedID == id, !Task.isCancelled else { return }
            detail.isStale = true; detail.failure = AppErrorMessage(error)
        }
    }
    /// Register only after the matching mutation receipt, using the session captured before dispatch.
    @discardableResult public func observeAcceptedRestore(_ receipt: TaskArchiveRecord, owner: UUID) -> Bool {
        guard owner == sessionOwner, receipt.state == "restore_queued" else { return false }
        pending[receipt.id] = Pending(taskID:receipt.taskId); removedAfterRestoreIDs.remove(receipt.id)
        return true
    }
    public func refresh() async {
        guard !isRefreshing, !Task.isCancelled else { return }
        let ticket = UUID(); readTicket = ticket; isRefreshing = true; list.isLoading = true
        defer { if readTicket == ticket { isRefreshing = false; list.isLoading = false } }
        do {
            let result = try await service.list(page:page,size:size,query:query,state:state)
            guard current(ticket) else { return }
            list.value = result; list.isStale = false; list.failure = nil; list.isLoading = false
            let selectable = Set(result.items.filter{!TaskArchiveSemantics.processing($0.state)}.map(\.id))
            selectedIDs.formIntersection(selectable)
        } catch {
            guard current(ticket) else { return }
            list.failure = AppErrorMessage(error); list.isStale = true; list.isLoading = false
        }
        guard current(ticket) else { return }
        await refreshSelected()
        guard current(ticket) else { return }
        // Snapshot token per receipt: replacing an accepted restore invalidates its older probe.
        let captured = pending.sorted{$0.key < $1.key}
        var failed = false
        for (id,receipt) in captured {
            guard current(ticket) else { return }
            do {
                let row = try await service.detail(id:id)
                guard current(ticket) else { return }
                guard pending[id]?.token == receipt.token else { continue }
                guard row.taskId == receipt.taskID else { throw BackendAPIError.invalidResponse }
            } catch {
                guard current(ticket) else { return }
                guard pending[id]?.token == receipt.token else { continue }
                if case BackendAPIError.status(404) = error {
                    pending.removeValue(forKey:id); removedAfterRestoreIDs.insert(id); reconciliationRevision = UUID()
                } else {
                    failed = true; reconciliationFailure = AppErrorMessage(error)
                    if case let BackendAPIError.status(code) = error, code == 401 || code == 403 { break }
                }
            }
        }
        if current(ticket), !failed { reconciliationFailure = nil }
    }
    public func run() async {
        guard pollTicket == nil, !Task.isCancelled else { return }
        let ticket = UUID(); pollTicket = ticket; isPolling = true
        defer { if pollTicket == ticket { pollTicket = nil; isPolling = false } }
        while pollTicket == ticket, !Task.isCancelled {
            await refresh()
            guard pollTicket == ticket, !Task.isCancelled else { return }
            do { try await sleep(.seconds(2)) } catch { return }
        }
    }
    public func stop() {
        pollTicket = nil; isPolling = false; invalidateReads(); viewOwner = UUID()
    }
    public func reset() {
        stop(); sessionOwner = UUID(); page = 1; size = 20; query = ""; state = nil
        list = .init(); detail = .init(); selectedID = nil; selectedIDs = []
        pending = [:]; removedAfterRestoreIDs = []; reconciliationFailure = nil; reconciliationRevision = UUID()
    }
    private func current(_ ticket: UUID) -> Bool { readTicket == ticket && !Task.isCancelled }
    private func invalidateReads() {
        readTicket = UUID(); detailTicket = UUID(); isRefreshing = false
        list.isLoading = false; list.isStale = true; detail.isLoading = false; detail.isStale = true
    }
    private func sameBytes(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs,rhs) { case (nil,nil): true; case let (a?,b?): a.utf8.elementsEqual(b.utf8); default: false }
    }
}
