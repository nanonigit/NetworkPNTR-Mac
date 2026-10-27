import ArtexCore
import Foundation
import Observation

/// Coalesce interactive refreshes behind read/write gates without cancelling a retained asset snapshot.
@MainActor @Observable final class FindingScreenReads {
    let store: FindingStore
    private(set) var isPending = false
    @ObservationIgnored private var active = false
    @ObservationIgnored private var forceTree = false
    @ObservationIgnored private var pending = false
    @ObservationIgnored private var pendingStats = false
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var watch: UUID?
    @ObservationIgnored private var pollTask: Task<Void,Never>?
    @ObservationIgnored private var pollTicket = UUID()
    init(store: FindingStore) { self.store = store }
    func activate() { guard !active else { return }; active = true; viewChanged() }
    func viewChanged() {
        guard active else { return }
        let previous = pollTask, owner = UUID(); pollTicket = owner; previous?.cancel()
        pollTask = Task { [weak self] in
            // Wait for the old loop's terminal cleanup before trying to acquire its poll ticket.
            await previous?.value
            guard let self, self.active, self.pollTicket == owner, !Task.isCancelled else { return }
            await self.store.runView()
        }
    }
    func request(forceTree: Bool = false,stats: Bool = false) {
        guard active else { return }
        pending = true; self.forceTree = self.forceTree || forceTree; pendingStats = pendingStats || stats; isPending = true; drain()
    }
    func stop() {
        active = false; ticket = UUID(); watch = nil; pending = false; forceTree = false; pendingStats = false
        pollTicket = UUID(); pollTask?.cancel()
        task?.cancel(); task = nil; isPending = false
    }
    private var available: Bool { !store.isMutating && !store.isRefreshingView && (store.view != .asset || !store.tree.isLoading) }
    private func drain() {
        guard active, pending, task == nil else { return }
        guard available else { observeGate(); return }
        watch = nil
        let owner = UUID(); ticket = owner
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.ticket == owner {
                    self.task = nil
                    if self.pending { self.drain() } else { self.isPending = false }
                }
            }
            while self.active, self.ticket == owner, self.pending, !Task.isCancelled {
                guard self.available else { self.observeGate(); return }
                let force = self.forceTree, stats = self.pendingStats; self.forceTree = false; self.pendingStats = false; self.pending = false
                await self.store.refreshView(forceTree:force)
                if stats, self.active, self.ticket == owner, !Task.isCancelled { await self.store.refreshStats() }
            }
        }
    }
    private func observeGate() {
        guard watch == nil else { return }
        let token = UUID(); watch = token
        withObservationTracking {
            _ = store.isMutating; _ = store.isRefreshingView; _ = store.view; _ = store.tree.isLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.watch == token else { return }; self.watch = nil; self.drain()
            }
        }
    }
}
