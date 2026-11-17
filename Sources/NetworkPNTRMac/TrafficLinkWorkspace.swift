import NetworkPNTRCore
import Foundation
import Observation

/// One modal owns its reads and target; the parent retains the uncertain-write ledger.
@MainActor @Observable final class TrafficLinkWorkspace: Identifiable {
    struct SearchTicket: Hashable {
        let dialog: UUID
        let generation: UUID
        let text: Data
        let page: Int64
    }
    let id = UUID()
    let binding: TrafficBindingStore
    let recoveryOnly: Bool
    private(set) var sourceIDs: [String]
    private(set) var selectedTarget: FindingRecord?
    private(set) var searchDraft = ""
    private(set) var pageNumber: Int64 = 1
    private(set) var candidates: FindingPage?
    private(set) var isLoading = false
    private(set) var isStale = true
    private(set) var failure: AppErrorMessage?
    private(set) var isSubmitting = false
    private(set) var isActive = true
    private var generation = UUID()
    private var loadedTicket: SearchTicket?
    @ObservationIgnored private weak var parent: TrafficScreenModel?
    @ObservationIgnored private let lease: UUID
    @ObservationIgnored private let initialOwner: UUID
    @ObservationIgnored private let initialRevision: UUID
    @ObservationIgnored private let findings: FindingService
    @ObservationIgnored private let sleep: TrafficScreenModel.Sleep
    @ObservationIgnored private var bindingOwner: UUID
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var queuedStop = false

    init(parent: TrafficScreenModel, lease: UUID, findings: FindingService, binding: TrafficBindingStore,
         sourceIDs: [String], recoveryOnly: Bool, sleep: @escaping TrafficScreenModel.Sleep) {
        self.parent = parent; self.lease = lease; self.findings = findings; self.binding = binding
        self.sourceIDs = sourceIDs; self.recoveryOnly = recoveryOnly; self.sleep = sleep
        initialOwner = parent.store.owner; initialRevision = parent.store.flowRevision; bindingOwner = binding.owner
    }
    var searchTicket: SearchTicket { .init(dialog: id, generation: generation, text: Data(searchDraft.utf8), page: pageNumber) }
    var pageIsCurrent: Bool { !isStale && loadedTicket == searchTicket }
    private var attached: Bool { isActive && !queuedStop && parent?.acceptsLink(id: id, lease: lease) == true && !Task.isCancelled }
    private var usable: Bool {
        attached && !changing && binding.owner == bindingOwner
            && parent?.linkScopeMatches(id: id, lease: lease, owner: initialOwner, revision: initialRevision) == true
    }
    var editable: Bool { usable && !recoveryOnly && !isSubmitting && !binding.isMutating && !binding.hasUnknownOutcome }
    var canSubmit: Bool { editable && selectedTarget?.canMutate == true && binding.canBind }
    private func update(_ body: () -> Void) {
        precondition(!changing)
        changing = true; body(); changing = false
        if queuedStop { queuedStop = false; stop() }
    }
    func start() { if !recoveryOnly { schedule() } }
    @discardableResult func edit(_ text: String) -> Bool {
        guard editable else { return false }
        if Data(text.utf8) == Data(searchDraft.utf8) { return true }
        update { searchDraft = text; pageNumber = 1; generation = UUID(); isStale = true }
        guard usable else { return false }; schedule(); return true
    }
    @discardableResult func page(_ delta: Int, ticket: SearchTicket) -> Bool {
        guard editable, pageIsCurrent, ticket == searchTicket, let candidates,
              delta == -1 && pageNumber > 1 || delta == 1 && pageNumber < (candidates.total > 0 ? (candidates.total - 1) / 20 + 1 : 1) else { return false }
        update { pageNumber += Int64(delta); generation = UUID(); isStale = true }
        guard usable else { return false }; schedule(); return true
    }
    func reloadCandidates(ticket: SearchTicket) { guard editable, ticket == searchTicket else { return }; schedule() }
    private func schedule() {
        guard usable, !recoveryOnly else { return }
        job?.cancel()
        let ticket = searchTicket, query = searchDraft, page = pageNumber
        update { isLoading = true; isStale = true; failure = nil }
        guard usable else { return }
        job = Task { [weak self, sleep] in
            do {
                try await sleep(.milliseconds(250))
                try Task.checkCancellation()
                guard let self, self.usable, self.searchTicket == ticket else { return }
                let result = try await self.findings.bindingCandidates(search: query, page: page)
                guard self.usable, self.searchTicket == ticket else { return }
                self.update { self.candidates = result; self.loadedTicket = ticket; self.isStale = false; self.isLoading = false }
            } catch {
                guard let self, self.usable, self.searchTicket == ticket else { return }
                self.update { self.isLoading = false; self.isStale = true; if !(error is CancellationError) { self.failure = AppErrorMessage(error) } }
            }
        }
    }
    @discardableResult func choose(_ identity: FindingRowIdentity, ticket: SearchTicket) async -> Bool {
        guard editable, !isLoading, pageIsCurrent, ticket == searchTicket,
              let row = candidates?.items.first(where: { $0.identity == identity }), row.canMutate else { return false }
        var selected = false
        update {
            selected = binding.select(row, sourceIDs: sourceIDs, owner: bindingOwner)
            if selected { bindingOwner = binding.owner; selectedTarget = row }
        }
        guard selected, usable else { return false }
        await binding.refresh(owner: bindingOwner)
        return usable && selectedTarget?.identity == identity && binding.canBind
    }
    @discardableResult func submit(id request: UUID, owner: UUID) async -> Bool {
        guard canSubmit, owner == bindingOwner, request == binding.requestID else { return false }
        let count = sourceIDs.count
        update { isSubmitting = true }
        defer { if isActive, !changing { update { isSubmitting = false } } }
        guard usable else { return false }
        let result = await binding.bind(id: request, owner: owner) { [weak self] in
            guard self?.usable == true else { throw CancellationError() }
        }
        guard attached else { return false }
        if case .confirmed = result {
            return parent?.finishLink(id: self.id, lease: lease, owner: initialOwner, revision: initialRevision, count: count) == true
        }
        return false
    }
    func recover(owner: UUID) async {
        guard attached, !changing, !isSubmitting, owner == bindingOwner, binding.owner == owner, binding.hasUnknownOutcome else { return }
        await binding.recover(owner: owner)
    }
    @discardableResult func acknowledge(owner: UUID, revision: UUID) -> Bool {
        guard attached, !changing, !isSubmitting, owner == bindingOwner, binding.owner == owner else { return false }
        let accepted = binding.acknowledge(owner: owner, revision: revision)
        guard accepted, attached else { return false }
        if recoveryOnly { return parent?.closeLink(id: id, lease: lease) == true }
        return true
    }
    func stop() {
        if changing { queuedStop = true; return }
        guard isActive else { return }
        // Invalidate before scrubbing observable fields so nested callbacks cannot act on this modal.
        update {
            isActive = false; job?.cancel(); job = nil; generation = UUID(); loadedTicket = nil
            sourceIDs = []; selectedTarget = nil; searchDraft = ""; candidates = nil
            isLoading = false; isStale = true; failure = nil; isSubmitting = false
            _ = binding.stop(ifOwnedBy: bindingOwner)
        }
    }
}
