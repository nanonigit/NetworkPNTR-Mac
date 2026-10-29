import ArtexCore
import Foundation

/// Each browser text field debounces independently; timers carry literal bytes and a revision.
enum TrafficTextField: CaseIterable, Hashable {
    case host, keyword, body, path, responseMinimum, responseMaximum
    static let advanced: [Self] = [.body, .path, .responseMinimum, .responseMaximum]
}

struct TrafficFilterTicket: Hashable {
    fileprivate let scope: UUID
    fileprivate let revision: UUID
    let field: TrafficTextField
    fileprivate let raw: Data
}

struct TrafficFilterProposal {
    let drafts: TrafficFilterDrafts
    let query: TrafficQuery
    let changed: Bool
}

/// A value-only proposal: adopt `drafts` only after the store accepts `query` for this presentation.
/// Scheduling, cancellation and presentation/mutation ownership are enforced by the screen model.
struct TrafficFilterDrafts {
    private struct Entry {
        var raw = Data()
        var applied = Data()
        var revision = UUID()
    }
    private let scope = UUID()
    private var entries: [TrafficTextField: Entry] = Dictionary(
        uniqueKeysWithValues: TrafficTextField.allCases.map { ($0, Entry()) }
    )

    func text(_ field: TrafficTextField) -> String {
        String(decoding: entries[field]!.raw, as: UTF8.self)
    }

    mutating func edit(_ field: TrafficTextField, text: String) {
        let bytes = Data(text.utf8)
        guard entries[field]!.raw != bytes else { return }
        entries[field]!.raw = bytes
        entries[field]!.revision = UUID()
    }

    func ticket(_ field: TrafficTextField) -> TrafficFilterTicket {
        let entry = entries[field]!
        return .init(scope: scope, revision: entry.revision, field: field, raw: entry.raw)
    }

    func proposal(for ticket: TrafficFilterTicket, query: TrafficQuery) -> TrafficFilterProposal? {
        guard ticket.scope == scope, ticket.revision == entries[ticket.field]!.revision,
              ticket.raw == entries[ticket.field]!.raw else { return nil }
        let value = ChatText.trim(String(decoding: ticket.raw, as: UTF8.self))
        let bytes = Data(value.utf8)
        let changed = bytes != entries[ticket.field]!.applied
        var drafts = self
        drafts.entries[ticket.field]!.applied = bytes
        var next = query
        switch ticket.field {
        case .host: next.host = value
        case .keyword: next.keyword = value
        case .body: next.body = value
        case .path: next.path = value
        case .responseMinimum: next.responseMinimum = Self.bound(value)
        case .responseMaximum: next.responseMaximum = Self.bound(value)
        }
        if changed { next.page = 0 }
        return .init(drafts: drafts, query: next, changed: changed)
    }

    func resetAdvanced(query: TrafficQuery) -> TrafficFilterProposal {
        var drafts = self
        let changed = query.status != nil || TrafficTextField.advanced.contains { !entries[$0]!.applied.isEmpty }
            || !query.body.isEmpty || !query.path.isEmpty || query.responseMinimum != nil || query.responseMaximum != nil
        for field in TrafficTextField.advanced { drafts.entries[field] = Entry() }
        var next = query
        next.body = ""; next.path = ""; next.responseMinimum = nil; next.responseMaximum = nil; next.status = nil
        if changed { next.page = 0 }
        return .init(drafts: drafts, query: next, changed: changed)
    }

    /// Go Atoi accepts ASCII signed decimal only. Negative values do not create range predicates.
    private static func bound(_ value: String) -> Int64? {
        var digits = value.utf8[...]
        if digits.first == 43 || digits.first == 45 { digits = digits.dropFirst() }
        guard !digits.isEmpty, digits.allSatisfy({ (48...57).contains($0) }),
              let number = Int64(value), number >= 0 else { return nil }
        return number
    }
}

/// Immediate controls use the applied query; they never flush pending text drafts.
enum TrafficFilterControl {
    case method(CapturedHTTPMethod?), status(TrafficStatusFilter?), size(Int), sort(TrafficSort)

    func applying(to query: TrafficQuery) -> TrafficQuery? {
        var next = query
        let changed: Bool
        switch self {
        case .method(let value):
            changed = value != query.method; next.method = value
        case .status(let value):
            changed = Self.statusToken(value) != Self.statusToken(query.status); next.status = value
        case .size(let value):
            guard [25, 50, 100, 200].contains(value) else { return nil }
            changed = value != query.size; next.size = value
        case .sort(let value):
            changed = true
            next.order = value == query.sort && query.order == .descending ? .ascending : .descending
            next.sort = value
        }
        if changed { next.page = 0 }
        return next
    }

    private static func statusToken(_ value: TrafficStatusFilter?) -> String? {
        switch value {
        case nil: nil
        case .informational: "1xx"
        case .success: "2xx"
        case .redirect: "3xx"
        case .clientError: "4xx"
        case .serverError: "5xx"
        case .exact(let code): String(code)
        }
    }
}
