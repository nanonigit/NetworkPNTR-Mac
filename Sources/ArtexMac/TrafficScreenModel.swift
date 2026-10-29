import ArtexCore
import Foundation
import Observation

/// A window retains this model; view bindings/tasks carry the lease returned by begin().
@MainActor @Observable final class TrafficScreenModel {
    typealias Sleep = @MainActor (Duration) async throws -> Void
    let store: TrafficStore
    private(set) var presentation: UUID?
    private(set) var drafts = TrafficFilterDrafts()
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

    init(store: TrafficStore, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.store = store; self.sleep = sleep
    }
    var controlsAvailable: Bool {
        presentation != nil && store.isActive && !changing && !tearingDown && !queuedStop && !queuedReset
            && !store.isMutating && store.confirmation == nil && !Task.isCancelled
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
        cancelTasks(); presentation = nil; drafts = TrafficFilterDrafts()
        if reset { store.resetSession() } else { store.stop() }
        tearingDown = false; resetting = false
    }
    @discardableResult func begin() -> UUID? {
        guard !changing, !tearingDown, !Task.isCancelled else { return nil }
        let lease = UUID()
        update {
            retire(reset: false)
            if !queuedReset { store.resume(); presentation = lease }
        }
        guard owns(lease) else { return nil }
        _ = refresh(lease: lease)
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
    private func drainReady(lease: UUID) {
        guard owns(lease) else { return }
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
            _ = store.confirmation; _ = store.isMutating; _ = store.isActive
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
        update { accepted = store.configure(query, owner: previous) }
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
        guard controlsAvailable, owns(lease), !store.isRefreshing else { return false }
        readTask?.cancel()
        let id = UUID(); readID = id
        readTask = Task { [weak self] in
            guard let self, self.owns(lease), self.readID == id else { return }
            await self.store.refresh()
            if self.readID == id { self.readTask = nil }
        }
        return true
    }
}
