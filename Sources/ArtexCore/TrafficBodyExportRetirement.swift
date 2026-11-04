import Foundation
import Observation

/// App-owned retirement survives individual detail windows and session screen replacement.
@MainActor @Observable package final class TrafficBodyExportRetirement {
    package struct Notice: Identifiable { package let id: UUID; package let message: AppErrorMessage }
    package private(set) var notices: [Notice] = []
    private var pending: [UUID: TrafficBodyExportModel] = [:]
    @ObservationIgnored private var seen: Set<UUID> = []
    package init() {}
    package var pendingCount: Int { pending.count }
    package func retain(_ model: TrafficBodyExportModel) {
        guard seen.insert(model.id).inserted else { return }
        pending[model.id] = model
        if model.isActive { model.stop() }
        watch(model.id)
    }
    private func watch(_ id: UUID) {
        guard let model = pending[id] else { return }
        if !model.isExporting {
            if model.cleanupRequired { notices.append(Notice(id: id, message: AppErrorMessage(key: .evidenceUICleanupFailed))) }
            pending[id] = nil
            return
        }
        withObservationTracking { _ = model.isExporting } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.watch(id) }
        }
    }
    package func dismiss(_ id: UUID) { notices.removeAll { $0.id == id } }
}
