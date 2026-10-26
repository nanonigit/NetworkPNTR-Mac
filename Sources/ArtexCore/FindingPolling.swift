import Foundation

extension FindingStore {
    public func runView() async {
        guard viewPollTicket == nil, !Task.isCancelled else { return }
        let ticket = UUID(); viewPollTicket = ticket; isPolling = true
        defer { if viewPollTicket == ticket { viewPollTicket = nil; isPolling = false } }
        while viewPollTicket == ticket, !Task.isCancelled {
            let owner = viewOwner
            await refreshView()
            guard viewPollTicket == ticket, !Task.isCancelled else { return }
            if owner != viewOwner { continue }
            if view == .asset { return }
            do { try await sleep(.seconds(5)) } catch { return }
        }
    }
    public func runStats() async {
        guard statsPollTicket == nil, !Task.isCancelled else { return }
        let ticket = UUID(); statsPollTicket = ticket; isStatsPolling = true
        defer { if statsPollTicket == ticket { statsPollTicket = nil; isStatsPolling = false } }
        while statsPollTicket == ticket, !Task.isCancelled {
            await refreshStats()
            guard statsPollTicket == ticket, !Task.isCancelled else { return }
            do { try await sleep(.seconds(5)) } catch { return }
        }
    }
    func stopPolling() { viewPollTicket = nil; statsPollTicket = nil; isPolling = false; isStatsPolling = false }
}
