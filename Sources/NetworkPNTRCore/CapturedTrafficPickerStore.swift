import Foundation
import Observation

/// Ordered cross-page selections and previews belong to one evidence owner; reads never bind or acknowledge writes.
@MainActor @Observable public final class CapturedTrafficPickerStore {
    public let catalog = FindingReadState<CapturedTrafficPage>()
    public let preview = FindingReadState<CapturedTrafficDetail>()
    public private(set) var owner = UUID()
    public private(set) var query = CapturedTrafficQuery()
    public private(set) var selectedPreviewID: String?
    public private(set) var failure: AppErrorMessage?
    public var isCurrent: Bool { active && evidence.isActive && parentOwner == evidence.owner }
    public var isSubmitting: Bool { write != nil }
    public var selectedIDs: [String] {
        let bound = boundIDs
        return selectedOrder.compactMap { bound.contains($0) ? nil : selectedValues[$0] }
    }
    public var selectedCount: Int { selectedIDs.count }
    public var canBind: Bool {
        isCurrent && !stopping && !resuming && !acquiring && !isSubmitting && !evidence.isMutating && evidence.canMutateSelected &&
        evidence.unknownIDs.isEmpty && !evidence.summary.isLoading && !evidence.summary.isStale &&
        evidence.summary.value != nil && selectedCount > 0
    }
    public var hasPrevious: Bool { canUseCatalog && query.page > 0 }
    public var hasNext: Bool {
        guard canUseCatalog, let total = catalog.value?.total, total > 0 else { return false }
        return query.page < (total - 1) / Int64(query.size)
    }
    private var selectedOrder: [Data] = []
    private var selectedValues: [Data: String] = [:]
    private var write: Ticket?
    @ObservationIgnored private let service: CapturedTrafficService
    @ObservationIgnored private let evidence: FindingTrafficStore
    @ObservationIgnored private var parentOwner: UUID
    private var active = true
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var resuming = false
    @ObservationIgnored private var stopAfterResume = false
    @ObservationIgnored private var acquiring = false
    private struct Ticket { let id = UUID(); let owner, parent: UUID }
    public init(service: CapturedTrafficService, evidence: FindingTrafficStore) {
        self.service = service; self.evidence = evidence; parentOwner = evidence.owner
    }
    private var boundIDs: Set<Data> { Set(evidence.summary.value?.bindings.map { Data($0.snapshot.sourceTrafficId.utf8) } ?? []) }
    private var canUseCatalog: Bool {
        isCurrent && !stopping && !resuming && !acquiring && !isSubmitting && !evidence.isMutating && !catalog.isLoading && !catalog.isStale && catalog.value != nil
    }
    private func usable(_ owner: UUID) -> Bool { isCurrent && !stopping && !resuming && self.owner == owner && !Task.isCancelled }
    private func owns(_ ticket: Ticket) -> Bool { usable(ticket.owner) && parentOwner == ticket.parent && write?.id == ticket.id }
    @discardableResult public func configure(_ value: CapturedTrafficQuery, owner: UUID) -> Bool {
        guard usable(owner), !acquiring, !isSubmitting, !evidence.isMutating else { return false }
        do {
            guard value.size == 25 else { throw FindingInputError.query }
            let path = try value.path(), previous = try query.path()
            if path == previous { return true }
        } catch { failure = AppErrorMessage(error); return false }
        acquiring = true
        defer { acquiring = false }
        query = value; self.owner = UUID(); catalog.invalidate(clear: true); clearPreview(); failure = nil
        return isCurrent
    }
    @discardableResult public func nextPage(owner: UUID) -> Bool {
        guard usable(owner), hasNext else { return false }
        var value = query; value.page += 1
        return configure(value, owner: owner)
    }
    @discardableResult public func previousPage(owner: UUID) -> Bool {
        guard usable(owner), hasPrevious else { return false }
        var value = query; value.page -= 1
        return configure(value, owner: owner)
    }
    @discardableResult public func toggle(id: String, selected: Bool, owner: UUID) -> Bool {
        guard usable(owner), canUseCatalog, catalog.value?.isUnavailable == false else { return false }
        let identity = Data(id.utf8)
        guard !boundIDs.contains(identity), let row = catalog.value?.exchanges.first(where: { $0.identity == identity }) else { return false }
        acquiring = true
        defer { acquiring = false }
        if selected {
            if selectedValues[identity] == nil { selectedValues[identity] = row.id; selectedOrder.append(identity) }
        } else { selectedValues.removeValue(forKey: identity); selectedOrder.removeAll { $0 == identity } }
        guard usable(owner) else { selectedOrder = []; selectedValues = [:]; return false }
        return true
    }
    @discardableResult public func selectPage(_ selected: Bool, owner: UUID) -> Bool {
        guard usable(owner), canUseCatalog, catalog.value?.isUnavailable == false else { return false }
        let ids = catalog.value?.exchanges.map(\.id) ?? []
        for id in ids where !boundIDs.contains(Data(id.utf8)) {
            guard toggle(id: id, selected: selected, owner: owner) else { return false }
        }
        return usable(owner)
    }
    @discardableResult public func clearSelection(owner: UUID) -> Bool {
        guard usable(owner), !acquiring, !isSubmitting else { return false }
        selectedOrder = []; selectedValues = [:]
        return usable(owner)
    }
    @discardableResult public func selectPreview(id: String?, owner: UUID) -> Bool {
        guard usable(owner), !acquiring else { return false }
        if let id {
            guard canUseCatalog, catalog.value?.exchanges.contains(where: { $0.identity == Data(id.utf8) }) == true else { return false }
        }
        selectedPreviewID = id; preview.invalidate(clear: true)
        guard usable(owner) else { clearPreview(); return false }
        return true
    }
    public func refreshCatalog() async {
        let owner = owner, value = query
        guard usable(owner), !isSubmitting, !evidence.isMutating else { return }
        _ = await catalog.refresh { [service] in
            guard self.usable(owner) else { throw CancellationError() }
            let result = try await service.list(value)
            guard self.usable(owner) else { throw CancellationError() }
            return result
        }
    }
    public func refreshPreview() async {
        let owner = owner
        guard usable(owner), !isSubmitting, !evidence.isMutating, let id = selectedPreviewID else { return }
        let identity = Data(id.utf8)
        _ = await preview.refresh { [service] in
            guard self.usable(owner), self.selectedPreviewID.map({ Data($0.utf8) }) == identity else { throw CancellationError() }
            let result = try await service.detail(id: id)
            guard self.usable(owner), self.selectedPreviewID.map({ Data($0.utf8) }) == identity else { throw CancellationError() }
            return result
        }
    }
    public func bind(owner: UUID) async -> FindingTrafficMutationOutcome {
        guard usable(owner), canBind else { return .notStarted }
        let refs = selectedIDs.map { FindingTrafficRef(trafficId: $0) }
        let ticket = Ticket(owner: owner, parent: parentOwner)
        acquiring = true; write = ticket; acquiring = false
        defer { if write?.id == ticket.id { write = nil } }
        guard owns(ticket) else { return .notStarted }
        failure = nil; catalog.invalidate(); preview.invalidate()
        let result = await evidence.apply(.bind(refs), owner: ticket.parent) {
            guard self.owns(ticket) else { throw CancellationError() }
        }
        if case .notStarted = result { return .notStarted }
        guard owns(ticket) else { return .discarded }
        switch result {
        case .confirmed:
            selectedOrder = []; selectedValues = [:]; clearPreview()
        case .invalidInput, .unconfirmed: failure = evidence.mutationFailure
        case .discarded, .notStarted: break
        }
        guard owns(ticket) else { failure = nil; return .discarded }
        return result
    }
    public func stop() {
        if resuming { stopAfterResume = true; return }
        guard !stopping, active else { return }
        stopping = true
        defer { stopping = false }
        active = false; owner = UUID()
        catalog.invalidate(clear: true); clearPreview(); selectedOrder = []; selectedValues = [:]; failure = nil
    }
    public func resume() {
        guard !stopping, !resuming, !active, !acquiring else { return }
        resuming = true
        parentOwner = evidence.owner; selectedOrder = []; selectedValues = [:]; owner = UUID(); active = true
        catalog.invalidate(clear: true); clearPreview()
        resuming = false
        if stopAfterResume { stopAfterResume = false; stop() }
    }
    private func clearPreview() { selectedPreviewID = nil; preview.invalidate(clear: true) }
}
