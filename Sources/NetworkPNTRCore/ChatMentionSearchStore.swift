import Foundation
import Observation

@MainActor @Observable public final class ChatMentionSearchStore {
    public private(set) var items: [ChatMention] = []
    public private(set) var nextCursor: String?
    public private(set) var loading = false
    public private(set) var loadingMore = false
    public var error: String? { failure?.text(language: .japanese) }
    public private(set) var failure: AppErrorMessage?
    public var pageError: String? { pageFailure?.text(language: .japanese) }
    public private(set) var pageFailure: AppErrorMessage?
    @ObservationIgnored private let service: ChatMentionService
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var kind: ChatMentionKind?
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var usedCursors: Set<String> = []
    public init(service: ChatMentionService) { self.service = service }
    private func message(_ error: any Error) -> AppErrorMessage { AppErrorMessage(error, fallback: .errorMentionSearch) }
    public func cancel() {
        generation = UUID(); loading = false; loadingMore = false
        items = []; nextCursor = nil; failure = nil; pageFailure = nil; usedCursors = []
    }
    public func search(kind: ChatMentionKind? = nil, query: String) async {
        cancel(); self.kind = kind; self.query = query
        let ticket = generation; loading = true
        defer { if ticket == generation { loading = false } }
        do {
            let page = try await service.search(kind: kind, query: query)
            guard ticket == generation, !Task.isCancelled else { return }
            items = page.items; nextCursor = page.nextCursor
        } catch {
            if ticket == generation, !Task.isCancelled { self.failure = message(error) }
        }
    }
    public func loadMore() async {
        guard !loading, !loadingMore, let cursor = nextCursor else { return }
        let ticket = generation; loadingMore = true; pageFailure = nil
        defer { if ticket == generation { loadingMore = false } }
        do {
            let page = try await service.search(kind: kind, query: query, cursor: cursor)
            guard ticket == generation, !Task.isCancelled else { return }
            if let next = page.nextCursor, next == cursor || usedCursors.contains(next) { throw BackendAPIError.invalidResponse }
            let seen = Set(items.map(\.identity))
            items.append(contentsOf: page.items.filter { !seen.contains($0.identity) })
            usedCursors.insert(cursor); nextCursor = page.nextCursor
        } catch {
            if ticket == generation, !Task.isCancelled { pageFailure = message(error) }
        }
    }
}
