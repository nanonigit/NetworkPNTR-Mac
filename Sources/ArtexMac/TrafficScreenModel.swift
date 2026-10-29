import ArtexCore
import Foundation
import Observation

/// A window retains this model; view bindings/tasks carry the lease returned by begin().
@MainActor @Observable final class TrafficScreenModel {
    typealias Sleep = @MainActor (Duration) async throws -> Void
    let store: TrafficStore
    let linking: TrafficBindingStore?
    private let findings: FindingService?
    private(set) var linkWorkspace: TrafficLinkWorkspace?
    private(set) var linkedCount: Int?
    private(set) var linkSelectionPreserved = false
    var linkHasUnknown: Bool { linking?.hasUnknownOutcome == true }
    var canOpenLink: Bool { findings != nil && linking != nil && !linkHasUnknown && !store.hasUnknownOutcome }

    private(set) var presentation: UUID?
    private(set) var previewRevision = UUID()
    private(set) var deletionDialog: TrafficConfirmation?
    private(set) var drafts = TrafficFilterDrafts()
    private var pendingSort: TrafficSortPreference?
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var tearingDown = false
    @ObservationIgnored private var resetting = false
    @ObservationIgnored private var ready: [TrafficTextField: TrafficFilterTicket] = [:]
    @ObservationIgnored private var gateWatch: UUID?
    @ObservationIgnored private var queuedStop = false
    @ObservationIgnored private var queuedReset = false
    @ObservationIgnored private var debounces: [TrafficTextField: Task<Void, Never>] = [:]
    @ObservationIgnored private var debounceIDs: [TrafficTextField: UUID] = [:]
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readID = UUID()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(store: TrafficStore, findings: FindingService? = nil, binding: FindingTrafficService? = nil, preferences: UserDefaults? = nil, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.store = store; self.findings = findings; self.linking = binding.map(TrafficBindingStore.init); self.preferences = preferences; self.sleep = sleep
    }
    var controlsAvailable: Bool { baseAvailable && pendingSort == nil && store.selectedExchange == nil }
    private var baseAvailable: Bool {
        presentation != nil && store.isActive && !changing && !tearingDown && !queuedStop && !queuedReset
            && linkWorkspace == nil && linking?.isMutating != true && !store.isMutating && store.confirmation == nil && deletionDialog == nil && !Task.isCancelled
    }
    var hasPendingText: Bool {
        TrafficTextField.allCases.contains {
            drafts.proposal(for: drafts.ticket($0), query: store.query)?.changed == true
        }
    }
    private func owns(_ lease: UUID) -> Bool {
        presentation == lease && store.isActive && !tearingDown && !queuedStop && !queuedReset && !Task.isCancelled
    }
    private func update(_ body: () -> Void) {
        precondition(!changing)
        changing = true; body(); changing = false
        if queuedReset { queuedReset = false; queuedStop = false; reset() }
        else if queuedStop, let lease = presentation { queuedStop = false; _ = stop(lease) }
        else { queuedStop = false }
    }
    private func cancelTasks() {
        for job in debounces.values { job.cancel() }
        debounces = [:]; debounceIDs = [:]; ready = [:]; gateWatch = nil
        readID = UUID(); readTask?.cancel(); readTask = nil
        pollTask?.cancel(); pollTask = nil
    }
    private func retire(reset: Bool) {
        tearingDown = true; resetting = reset
        linkWorkspace?.stop(); linkWorkspace = nil
        if reset { linking?.resetSession() } else { linking?.stop() }
        linkedCount = nil; linkSelectionPreserved = false
        cancelTasks(); presentation = nil; pendingSort = nil; drafts = TrafficFilterDrafts(); previewRevision = UUID(); deletionDialog = nil
        if reset { store.resetSession() } else { store.stop() }
        tearingDown = false; resetting = false
    }
    @discardableResult func begin() -> UUID? {
        guard !changing, !tearingDown, !Task.isCancelled else { return nil }
        let lease = UUID()
        update {
            retire(reset: false)
            if !queuedReset {
                store.resume()
                if !queuedReset { pendingSort = preferences.map(TrafficSortPreference.read); presentation = lease }
            }
        }
        guard owns(lease) else { return nil }
        if restoreSort(lease: lease) { _ = refresh(lease: lease) }
        guard owns(lease) else { return nil }
        pollTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do { try await sleep(.seconds(5)) } catch { return }
                guard let self, self.owns(lease) else { return }
                if self.store.canAutoRefresh { _ = self.refresh(lease: lease) }
            }
        }
        return lease
    }
    @discardableResult func stop(_ lease: UUID) -> Bool {
        guard presentation == lease, !tearingDown else { return false }
        if changing { queuedStop = true; return true }
        update { retire(reset: false) }; return true
    }
    func reset() {
        if tearingDown { if !resetting { queuedReset = true }; return }
        if changing { queuedReset = true; return }
        update { retire(reset: true) }
    }
    func text(_ field: TrafficTextField, lease: UUID) -> String {
        owns(lease) ? drafts.text(field) : ""
    }
    @discardableResult func edit(_ field: TrafficTextField, text: String, lease: UUID) -> Bool {
        guard controlsAvailable, owns(lease) else { return false }
        let previous = drafts.ticket(field)
        var next = drafts; next.edit(field, text: text)
        let ticket = next.ticket(field)
        if previous == ticket { return true }
        update { ready[field] = nil; drafts = next }
        guard owns(lease) else { return false }
        debounces[field]?.cancel()
        let id = UUID(); debounceIDs[field] = id
        debounces[field] = Task { [weak self, sleep] in
            do { try await sleep(.milliseconds(300)) } catch { return }
            guard let self, self.owns(lease), self.debounceIDs[field] == id else { return }
            self.ready[field] = ticket
            self.drainReady(lease: lease)
            if self.debounceIDs[field] == id {
                self.debounces[field] = nil; self.debounceIDs[field] = nil
            }
        }
        return true
    }
    private func restoreSort(lease: UUID) -> Bool {
        guard let saved = pendingSort else { return true }
        guard baseAvailable, owns(lease), !changing else {
            if owns(lease), !changing { observeGate(lease: lease) }
            return false
        }
        let query = saved.applying(to: store.query)
        var accepted = false
        update {
            accepted = store.configure(query, owner: store.owner)
            if accepted, owns(lease) {
                pendingSort = nil
                if owns(lease) { TrafficSortPreference(query: query).write(preferences) }
            }
        }
        return accepted && owns(lease)
    }
    private func drainReady(lease: UUID) {
        guard owns(lease) else { return }
        let restoring = pendingSort != nil
        guard restoreSort(lease: lease) else { return }
        if restoring { _ = refresh(lease: lease) }
        for field in TrafficTextField.allCases {
            guard let ticket = ready[field] else { continue }
            guard controlsAvailable else { observeGate(lease: lease); return }
            if ticket == drafts.ticket(field) { _ = apply(ticket, lease: lease) }
            guard owns(lease) else { return }
            ready[field] = nil
        }
        gateWatch = nil
    }
    private func observeGate(lease: UUID) {
        guard gateWatch == nil else { return }
        let id = UUID(); gateWatch = id
        withObservationTracking {
            _ = store.confirmation; _ = store.isMutating; _ = store.isActive; _ = deletionDialog; _ = store.selectedExchange; _ = linkWorkspace; _ = linking?.isMutating
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.gateWatch == id, self.owns(lease) else { return }
                self.gateWatch = nil; self.drainReady(lease: lease)
            }
        }
    }
    private func apply(_ ticket: TrafficFilterTicket, lease: UUID) -> Bool {
        guard controlsAvailable, owns(lease), let proposal = drafts.proposal(for: ticket, query: store.query) else { return false }
        return adopt(proposal, lease: lease)
    }
    private func adopt(_ proposal: TrafficFilterProposal, lease: UUID) -> Bool {
        var accepted = false
        update {
            guard store.configure(proposal.query, owner: store.owner), owns(lease) else { return }
            drafts = proposal.drafts
            accepted = true
        }
        guard accepted, owns(lease) else { return false }
        if proposal.changed { _ = refresh(lease: lease) }
        return true
    }
    @discardableResult func control(_ control: TrafficFilterControl, lease: UUID) -> Bool {
        guard controlsAvailable, owns(lease), let query = control.applying(to: store.query) else { return false }
        let previous = store.owner
        var accepted = false
        update {
            accepted = store.configure(query, owner: previous)
            if accepted, owns(lease), case .sort = control { TrafficSortPreference(query: query).write(preferences) }
        }
        guard accepted, owns(lease) else { return false }
        if store.owner != previous { _ = refresh(lease: lease) }
        return true
    }
    @discardableResult func resetAdvanced(lease: UUID) -> Bool {
        guard controlsAvailable, owns(lease) else { return false }
        let proposal = drafts.resetAdvanced(query: store.query)
        guard adopt(proposal, lease: lease) else { return false }
        for field in TrafficTextField.advanced {
            debounces[field]?.cancel(); debounces[field] = nil; debounceIDs[field] = nil; ready[field] = nil
        }
        return true
    }
    @discardableResult func page(_ delta: Int, lease: UUID) -> Bool {
        guard controlsAvailable, owns(lease), (delta == -1 && store.hasPrevious) || (delta == 1 && store.hasNext) else { return false }
        var query = store.query; query.page += Int64(delta)
        var accepted = false
        update { accepted = store.configure(query, owner: store.owner) }
        guard accepted, owns(lease) else { return false }
        _ = refresh(lease: lease); return true
    }
    @discardableResult func refresh(lease: UUID) -> Bool {
        guard baseAvailable, owns(lease), !store.isRefreshing, restoreSort(lease: lease), owns(lease) else { return false }
        readTask?.cancel()
        let id = UUID(); readID = id
        readTask = Task { [weak self] in
            guard let self, self.owns(lease), self.readID == id else { return }
            await self.store.refresh()
            if self.readID == id { self.readTask = nil }
        }
        return true
    }
    @discardableResult func page(_ delta: Int, lease: UUID, owner: UUID) -> Bool {
        guard store.owner == owner else { return false }; return page(delta, lease: lease)
    }
    @discardableResult func resetAdvanced(lease: UUID, owner: UUID) -> Bool {
        guard store.owner == owner else { return false }; return resetAdvanced(lease: lease)
    }
    func canUseRecords(lease: UUID, owner: UUID) -> Bool {
        controlsAvailable && owns(lease) && store.owner == owner && !hasPendingText
    }
    @discardableResult func toggleHost(_ host: String, selected: Bool, lease: UUID, owner: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner) else { return false }
        var accepted = false
        update { accepted = store.toggleHost(host, selected: selected, owner: owner) }
        return accepted && owns(lease) && store.owner == owner
    }
    @discardableResult func selectHosts(_ selected: Bool, lease: UUID, owner: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner) else { return false }
        var accepted = false
        update { accepted = store.selectAllHosts(selected, owner: owner) }
        return accepted && owns(lease) && store.owner == owner
    }
    func selectDetail(_ id: String, lease: UUID, owner: UUID) async {
        guard canUseRecords(lease: lease, owner: owner) else { return }
        var accepted = false
        update {
            accepted = store.selectExchange(id: id, owner: owner)
            if accepted && owns(lease) { previewRevision = UUID() }
        }
        guard accepted, owns(lease), store.owner == owner else { return }
        await store.refreshDetail()
    }
    func closeDetail(_ id: String, lease: UUID, owner: UUID, revision: UUID) {
        guard baseAvailable, owns(lease), store.owner == owner, previewRevision == revision,
              store.selectedExchange?.identity == Data(id.utf8) else { return }
        update {
            if store.selectExchange(id: nil, owner: owner), owns(lease) { previewRevision = UUID() }
        }
    }
    @discardableResult func prepareDeletion(_ intent: TrafficIntent, lease: UUID, owner: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner), !linkHasUnknown else { return false }
        if case .capture = intent { return false }
        var accepted = false
        update {
            accepted = store.prepare(intent, owner: owner)
            if accepted && owns(lease) { deletionDialog = store.confirmation }
        }
        return accepted && owns(lease) && deletionDialog != nil
    }
    @discardableResult func cancelDeletion(id: UUID, lease: UUID, owner: UUID) -> Bool {
        guard owns(lease), !changing, !store.isMutating, deletionDialog?.id == id else { return false }
        var accepted = false
        update {
            accepted = store.cancelConfirmation(id: id, owner: owner)
            if accepted && owns(lease) { deletionDialog = nil }
        }
        return accepted && owns(lease)
    }
    func confirmDeletion(id: UUID, lease: UUID, owner: UUID) async -> TrafficMutationOutcome {
        guard owns(lease), !changing, !store.isMutating, !linkHasUnknown, linking?.isMutating != true, linkWorkspace == nil, store.owner == owner,
              deletionDialog?.id == id, store.confirmation?.id == id else { return .notStarted }
        if case .capture = deletionDialog?.change { return .notStarted }
        let result = await store.confirm(id: id, owner: owner)
        guard owns(lease), !changing else { return .discarded }
        update { if deletionDialog?.id == id { deletionDialog = nil } }
        guard owns(lease) else { return .discarded }
        if case .confirmed = result { _ = refresh(lease: lease) }
        return result
    }
    @discardableResult func acknowledge(lease: UUID, owner: UUID, revision: UUID) -> Bool {
        guard controlsAvailable, owns(lease), store.owner == owner, !hasPendingText else { return false }
        var accepted = false
        update { accepted = store.acknowledgeUnknown(owner: owner, revision: revision) }
        return accepted && owns(lease)
    }

    @discardableResult func toggleFlow(_ id: String, selected: Bool, lease: UUID, owner: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner) else { return false }
        var accepted = false
        update { accepted = store.toggleFlow(id: id, selected: selected, owner: owner) }
        return accepted && owns(lease) && store.owner == owner
    }
    @discardableResult func clearFlows(lease: UUID, owner: UUID, revision: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner), store.flowRevision == revision else { return false }
        var accepted = false
        update { accepted = store.clearFlowSelection(owner: owner) }
        return accepted && owns(lease)
    }
    @discardableResult func selectVisibleFlows(_ selected: Bool, lease: UUID, owner: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner) else { return false }
        var accepted = false
        update { accepted = store.selectVisibleFlows(selected, owner: owner) }
        return accepted && owns(lease)
    }
    @discardableResult func openLink(lease: UUID, owner: UUID, revision: UUID) -> Bool {
        guard canUseRecords(lease: lease, owner: owner), canOpenLink, store.flowRevision == revision,
              !store.selectedFlowIDs.isEmpty, let findings, let linking else { return false }
        return presentLink(lease: lease, findings: findings, binding: linking, recoveryOnly: false)
    }
    @discardableResult func openLinkRecovery(lease: UUID) -> Bool {
        guard baseAvailable, owns(lease), linkHasUnknown, let findings, let linking else { return false }
        return presentLink(lease: lease, findings: findings, binding: linking, recoveryOnly: true)
    }
    private func presentLink(lease: UUID, findings: FindingService, binding: TrafficBindingStore, recoveryOnly: Bool) -> Bool {
        var next: TrafficLinkWorkspace?
        update {
            binding.resume()
            guard owns(lease), !binding.isMutating else { return }
            let workspace = TrafficLinkWorkspace(parent: self, lease: lease, findings: findings, binding: binding,
                sourceIDs: recoveryOnly ? [] : store.selectedFlowIDs, recoveryOnly: recoveryOnly, sleep: sleep)
            linkWorkspace = workspace; linkedCount = nil; linkSelectionPreserved = false; next = workspace
        }
        guard let next, acceptsLink(id: next.id, lease: lease) else { return false }
        next.start(); return true
    }
    func acceptsLink(id: UUID, lease: UUID) -> Bool {
        owns(lease) && !changing && linkWorkspace?.id == id
    }
    func linkScopeMatches(id: UUID, lease: UUID, owner: UUID, revision: UUID) -> Bool {
        acceptsLink(id: id, lease: lease) && store.owner == owner && store.flowRevision == revision
            && !store.isMutating && deletionDialog == nil && store.selectedExchange == nil && !store.hasUnknownOutcome
    }
    @discardableResult func closeLink(id: UUID, lease: UUID) -> Bool {
        guard acceptsLink(id: id, lease: lease), let workspace = linkWorkspace,
              !workspace.isSubmitting, !workspace.binding.isMutating else { return false }
        update { workspace.stop(); linkWorkspace = nil }
        return owns(lease)
    }
    /// Called only after the binding store has verified a complete receipt.
    func finishLink(id: UUID, lease: UUID, owner: UUID, revision: UUID, count: Int) -> Bool {
        guard acceptsLink(id: id, lease: lease), let workspace = linkWorkspace else { return false }
        var cleared = false
        update {
            if store.owner == owner, store.flowRevision == revision {
                cleared = store.clearFlowSelection(owner: owner)
            }
            guard owns(lease), !queuedStop, !queuedReset else { return }
            linkedCount = count; linkSelectionPreserved = !cleared
            workspace.stop(); linkWorkspace = nil
        }
        return cleared && owns(lease)
    }

}
