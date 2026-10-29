import ArtexCore
import Foundation

/// Nonprivate browser-equivalent sort fields only; never encode a whole query or draft.
struct TrafficSortPreference: Codable {
    static let key = "traffic.sort.preference.v1"
    private let field: String
    private let direction: String
    init(query: TrafficQuery) { field = query.sort.rawValue; direction = query.order.rawValue }
    private var choice: (TrafficSort, TrafficSortOrder)? {
        guard let field = TrafficSort(rawValue: field), let direction = TrafficSortOrder(rawValue: direction) else { return nil }
        return (field, direction)
    }
    static func read(_ preferences: UserDefaults) -> Self {
        guard let data = preferences.data(forKey: key), data.count <= 4096,
              let saved = try? JSONDecoder().decode(Self.self, from: data), saved.choice != nil else {
            return .init(query: TrafficQuery())
        }
        return saved
    }
    func applying(to query: TrafficQuery) -> TrafficQuery {
        var next = query
        let selected = choice ?? (.timestamp, .descending)
        next.sort = selected.0; next.order = selected.1; next.page = 0
        return next
    }
    func write(_ preferences: UserDefaults?) {
        // Only built-in String fields are encoded; storage remains best effort like the browser helper.
        guard let preferences, let data = try? JSONEncoder().encode(self) else { return }
        preferences.set(data, forKey: Self.key)
    }
}
