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
        debounces = [:]; debounceIDs = [:]
        readID = UUID(); readTask?.cancel(); readTask = nil
        pollTask?.cancel(); pollTask = nil
    }
    private func retire(reset: Bool) {
        tearingDown = true
        cancelTasks(); presentation = nil; drafts = TrafficFilterDrafts()
        if reset { store.resetSession() } else { store.stop() }
        tearingDown = false
    }
    @discardableResult func begin() -> UUID? {
        guard !changing, !tearingDown, !Task.isCancelled else { return nil }
        let lease = UUID()
        update {
            retire(reset: false)
            store.resume()
            if !queuedReset { presentation = lease }
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
        guard !tearingDown else { return }
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
        update { drafts = next }
        guard owns(lease) else { return false }
        debounces[field]?.cancel()
        let id = UUID(); debounceIDs[field] = id
        debounces[field] = Task { [weak self, sleep] in
            do { try await sleep(.milliseconds(300)) } catch { return }
            guard let self, self.owns(lease), self.debounceIDs[field] == id else { return }
            _ = self.apply(ticket, lease: lease)
            if self.debounceIDs[field] == id {
                self.debounces[field] = nil; self.debounceIDs[field] = nil
            }
        }
        return true
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
            debounces[field]?.cancel(); debounces[field] = nil; debounceIDs[field] = nil
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
