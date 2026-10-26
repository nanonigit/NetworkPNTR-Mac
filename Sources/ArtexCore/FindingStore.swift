import Foundation
import Observation

public enum FindingView: String, CaseIterable, Sendable { case flat, grouped, asset }
public struct FindingDetailSelection: Equatable, Sendable {
    public let id: String
    public let contextTaskID: String?
}

/// Retained state for the three browser findings views; no read changes the active task.
@MainActor @Observable public final class FindingStore {
    public private(set) var view = FindingView.flat
    public private(set) var filters = FindingQuery()
    public let flat = FindingPageState<FindingPage>(size:20,maximum:200)
    public let groups = FindingPageState<FindingGroupsPage>(size:10,maximum:100)
    public let tree = FindingReadState<FindingAssetTree>()
    public let stats = FindingReadState<FindingStats>()
    public let detail = FindingReadState<FindingRecord>()
    public private(set) var groupPages: [String:FindingPageState<FindingPage>] = [:]
    public private(set) var expandedGroups = Set<String>()
    public internal(set) var selectedIDs = Set<String>()
    public private(set) var assetScope: String?
    public internal(set) var selectedDetail: FindingDetailSelection?
    public private(set) var viewOwner = UUID()
    public private(set) var sessionOwner = UUID()
    public private(set) var configurationFailure: AppErrorMessage?
    public internal(set) var isMutating = false
    public internal(set) var unknownIDs = Set<String>()
    public internal(set) var lastConfirmation: FindingConfirmedMutation?
    public internal(set) var mutationFailure: AppErrorMessage?
    @ObservationIgnored var mutationTicket: FindingMutationTicket?
    public private(set) var isRefreshingView = false
    public internal(set) var isPolling = false
    public internal(set) var isStatsPolling = false
    @ObservationIgnored var viewPollTicket: UUID?
    @ObservationIgnored var statsPollTicket: UUID?
    @ObservationIgnored let service: FindingService
    @ObservationIgnored let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored var activityOwner = UUID()
    @ObservationIgnored private var viewReadTicket = UUID()
    public init(service: FindingService,sleep: @escaping @MainActor (Duration) async throws -> Void = {try await Task.sleep(for:$0)}) {
        self.service = service; self.sleep = sleep
    }
    @discardableResult public func configureFilters(_ query: FindingQuery) -> Bool {
        guard !isMutating, !Task.isCancelled else { return false }
        var copy = query; copy.page = 1; copy.size = 20; copy.assetScope = nil
        do {
            let fingerprint = Data(try copy.path("/filters",maximum:200,includeScope:false).utf8)
            // Use the same normalized path shape for defaults and subsequent filter comparisons.
            let current = Data(try filters.path("/filters",maximum:200,includeScope:false).utf8)
            filters = copy; configurationFailure = nil
            guard current != fingerprint else { return true }
            invalidateReads(); viewOwner = UUID()
            _ = flat.configure(page:1,size:flat.size); flat.read.invalidate(clear:true)
            _ = groups.configure(page:1,size:groups.size); groups.read.invalidate(clear:true)
            groupPages = [:]; expandedGroups = []; tree.invalidate(clear:true); assetScope = nil
            detail.invalidate(clear:true); selectedDetail = nil; return true
        } catch { configurationFailure = AppErrorMessage(error); return false }
    }
    @discardableResult public func setView(_ next: FindingView) -> Bool {
        guard !isMutating, !Task.isCancelled else { return false }
        guard view != next else { return true }
        let previousScope = view == .asset ? assetScope : nil
        view = next; invalidateReads(); viewOwner = UUID()
        if !sameBytes(previousScope,view == .asset ? assetScope : nil) { flat.read.invalidate(clear:true) }
        return true
    }
    @discardableResult public func configureFlat(page: Int64,size: Int) -> Bool {
        guard !isMutating, !Task.isCancelled else { return false }
        let previous = (flat.page,flat.size)
        guard flat.configure(page:page,size:size) else { configurationFailure = .init(key:.findingLimits); return false }
        if previous != (page,size) { invalidateReads(); viewOwner = UUID() }; configurationFailure = nil; return true
    }
    @discardableResult public func configureGroups(page: Int64,size: Int) -> Bool {
        guard !isMutating, !Task.isCancelled else { return false }
        let previous = (groups.page,groups.size)
        guard groups.configure(page:page,size:size) else { configurationFailure = .init(key:.findingLimits); return false }
        if previous != (page,size) { invalidateReads(); viewOwner = UUID() }; configurationFailure = nil; return true
    }
    @discardableResult public func configureGroup(_ key: String,page: Int64,size: Int,owner: UUID) -> Bool {
        guard !isMutating, !Task.isCancelled, owner == viewOwner, view == .grouped, visibleGroupKeys.contains(key),
              expandedGroups.contains(key), let state = groupPages[key] else { return false }
        return state.configure(page:page,size:size)
    }
    public func setGroupExpanded(_ key: String,expanded: Bool,owner: UUID) async {
        guard !isMutating, !Task.isCancelled, owner == viewOwner, view == .grouped, visibleGroupKeys.contains(key) else { return }
        if !expanded { expandedGroups.remove(key); groupPages[key]?.read.invalidate(); return }
        expandedGroups.insert(key)
        if groupPages[key] == nil { groupPages[key] = .init(size:10,maximum:200) }
        if groupPages[key]?.read.value == nil { await refreshGroup(key) }
    }
    public func refreshGroup(_ key: String) async {
        guard !isMutating, !Task.isCancelled, view == .grouped, visibleGroupKeys.contains(key), expandedGroups.contains(key), let state = groupPages[key] else { return }
        var query = filters; query.task = key; query.assetScope = nil
        let captured = query
        await state.refresh { [service] page,size in var q = captured; q.page = page; q.size = size; return try await service.list(q) }
    }
    @discardableResult public func selectAsset(_ key: String?,owner: UUID) -> Bool {
        guard !isMutating, !Task.isCancelled, owner == viewOwner, view == .asset else { return false }
        if let key, tree.value?.nodes.contains(where:{$0.key.utf8.elementsEqual(key.utf8)}) != true { return false }
        guard !sameBytes(assetScope,key) else { return true }
        assetScope = key; invalidateReads(); viewOwner = UUID(); _ = flat.configure(page:1,size:flat.size); flat.read.invalidate(clear:true)
        return true
    }
    public func setSelected(_ id: String,selected: Bool,owner: UUID) {
        guard !isMutating, owner == viewOwner else { return }
        if selected {
            guard visibleRecords.contains(where:{$0.findingId == id && $0.standalone}) else { return }; selectedIDs.insert(id)
        } else { selectedIDs.remove(id) }
    }
    public func setAllVisible(selected: Bool,owner: UUID) {
        guard !isMutating, owner == viewOwner else { return }
        for row in visibleRecords { if let id = row.findingId { setSelected(id,selected:selected,owner:owner) } }
    }
    public func clearSelection() { guard !isMutating else { return }; selectedIDs = [] }
    public func select(id: String?,contextTaskID: String? = nil,owner: UUID) async {
        guard !isMutating, !Task.isCancelled, owner == viewOwner else { return }
        do {
            let next = try id.map { FindingDetailSelection(id:try FindingWire.canonicalID($0),contextTaskID:try contextTaskID.map(FindingWire.canonicalID)) }
            if selectedDetail != next { selectedDetail = next; detail.invalidate(clear:true) }
            await refreshSelected()
        } catch { configurationFailure = AppErrorMessage(error) }
    }
    public func refreshSelected() async {
        guard !isMutating, let selection = selectedDetail else { return }
        await detail.refresh { [service] in try await service.detail(id:selection.id,contextTaskID:selection.contextTaskID) }
    }
    public func refreshStats() async {
        guard !isMutating else { return }
        await stats.refresh { [service] in try await service.stats() }
    }
    public func refreshView() async {
        guard !isMutating, !isRefreshingView, !Task.isCancelled else { return }
        let ticket = UUID(); viewReadTicket = ticket; isRefreshingView = true
        defer { if viewReadTicket == ticket { isRefreshingView = false } }
        switch view {
        case .flat: await refreshFlat()
        case .asset:
            let query = filters; await tree.refresh { [service] in try await service.assetTree(query) }
            guard current(ticket) else { return }; await refreshFlat()
        case .grouped:
            let query = filters
            await groups.refresh { [service] page,size in var q = query; q.page = page; q.size = size; return try await service.groups(q) }
            guard current(ticket) else { return }
            let keys = expandedGroups.intersection(visibleGroupKeys).sorted()
            for key in keys where groupPages[key]?.read.value != nil {
                guard current(ticket) else { return }; await refreshGroup(key)
            }
        }
        guard current(ticket) else { return }; await refreshSelected()
    }
    public func stop() { stopPolling(); invalidateReads(includeStats:true); activityOwner = UUID(); viewOwner = UUID() }
    public func reset() {
        stop(); sessionOwner = UUID(); view = .flat; filters = .init()
        flat.reset(); groups.reset(); groupPages = [:]; expandedGroups = []
        tree.invalidate(clear:true); stats.invalidate(clear:true); detail.invalidate(clear:true)
        selectedDetail = nil; selectedIDs = []; assetScope = nil; configurationFailure = nil
        unknownIDs = []; lastConfirmation = nil; mutationFailure = nil
    }
    var visibleRecords: [FindingRecord] {
        if view != .grouped { return flat.read.value?.items ?? [] }
        return expandedGroups.intersection(visibleGroupKeys).sorted().flatMap{groupPages[$0]?.read.value?.items ?? []}
    }
    var visibleGroupKeys: Set<String> { Set(groups.read.value?.items.map{$0.taskId ?? "__unassigned__"} ?? []) }
    func invalidateReads(includeStats: Bool = false) {
        viewReadTicket = UUID(); isRefreshingView = false
        flat.read.invalidate(); groups.read.invalidate(); tree.invalidate(); detail.invalidate()
        if includeStats { stats.invalidate() }
        for page in groupPages.values { page.read.invalidate() }
    }
    private func refreshFlat() async {
        var query = filters; query.assetScope = view == .asset ? assetScope : nil; let captured = query
        await flat.refresh { [service] page,size in var q = captured; q.page = page; q.size = size; return try await service.list(q) }
    }
    private func current(_ ticket: UUID) -> Bool { viewReadTicket == ticket && !Task.isCancelled }
    private func sameBytes(_ a: String?,_ b: String?) -> Bool {
        switch (a,b) { case (nil,nil): true; case let (a?,b?): a.utf8.elementsEqual(b.utf8); default: false }
    }
}
