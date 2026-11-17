import NetworkPNTRCore
import Foundation

/// Browser-equivalent preferences only. Transient search, cursors and private drafts are excluded.
struct FindingScreenPreferences: Codable {
    let version: Int
    let view: String
    let severity: String?
    let status: String?
    let vulnclass: String
    let task: String
    let sort: String

    @MainActor init(store: FindingStore) {
        version = 1; view = store.view.rawValue; severity = store.filters.severity?.rawValue
        status = store.filters.status?.rawValue; vulnclass = store.filters.vulnclass
        task = store.filters.task; sort = store.filters.sort.rawValue
    }
    func validated() -> (FindingView,FindingQuery)? {
        let knownSeverity = severity.flatMap(FindingSeverity.init(rawValue:))
        let knownStatus = status.flatMap(FindingStatus.init(rawValue:))
        guard version == 1, let view = FindingView(rawValue:view), let sort = FindingSort(rawValue:sort),
              severity == nil || knownSeverity != nil, status == nil || knownStatus != nil,
              vulnclass.utf8.count <= 8192,
              task == "all" || task == "__unassigned__" || Self.canonicalID(task) else { return nil }
        return (view,.init(severity:knownSeverity,status:knownStatus,vulnclass:vulnclass,task:task,sort:sort))
    }
    private static func canonicalID(_ value: String) -> Bool {
        guard let number = Int64(value), number > 0 else { return false }; return String(number) == value
    }
}
