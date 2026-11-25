import Foundation
import Observation

@MainActor @Observable public final class GuestLogStore {
    public var paused = false
    public private(set) var rows: [GuestLogEntry] = []
    public private(set) var isRefreshing = false
    public private(set) var isLoadingHistory = false
    public private(set) var hasLoaded = false
    public private(set) var liveHistoryGap = false
    public private(set) var recentFailure: AppErrorMessage?
    public private(set) var historyFailure: AppErrorMessage?
    private var historyExhausted = false
    private var olderBoundary: Int64?
    private var cursor: Int64 = 0
    private var displayGeneration = UUID()
    private let service: GuestLogService

    public init(service: GuestLogService) { self.service = service }

    private var historyBoundary: Int64? { olderBoundary ?? rows.compactMap(\.dbId).min() }

    public var canLoadOlder: Bool { !historyExhausted && (historyBoundary ?? 0) > 1 }

    public func filtered(keyword: String, level: GuestLogLevel?) -> [GuestLogEntry] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter {
            (level == nil || $0.level == level?.rawValue)
                && (needle.isEmpty || $0.text.lowercased().contains(needle) || $0.tag.lowercased().contains(needle))
        }
    }

    public func clear() {
        displayGeneration = UUID()
        rows.removeAll()
        liveHistoryGap = false
        olderBoundary = nil
        historyExhausted = false
        historyFailure = nil
    }

    public func refresh() async {
        guard !Task.isCancelled, !isRefreshing, !isLoadingHistory else { return }
        let generation = displayGeneration
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let followsEarlierSnapshot = hasLoaded
            let previousCursor = cursor
            var page = try await service.recent(since: previousCursor)
            if followsEarlierSnapshot, page.hasGap(after: previousCursor), !paused, generation == displayGeneration {
                do {
                    let expanded = try await service.recent(since: previousCursor, includeFullRing: true)
                    guard expanded.cursor >= page.cursor || expanded.cursor < previousCursor else {
                        throw BackendAPIError.invalidResponse
                    }
                    page = expanded
                } catch RuntimeError.integrity("JSON response size") {
                    // Keep the valid smaller snapshot and surface its known gap.
                }
            }
            hasLoaded = true
            recentFailure = nil
            if page.cursor < cursor {
                clear()
                cursor = 0
                hasLoaded = false
                return
            }
            cursor = page.cursor
            guard !paused, generation == displayGeneration else { return }
            if followsEarlierSnapshot, page.hasGap(after: previousCursor) { liveHistoryGap = true }
            guard !page.items.isEmpty else { return }
            rows = Self.merge(rows, page.items, cap: GuestLogService.liveCapacity)
            if let earliest = rows.compactMap(\.dbId).min(), let olderBoundary, olderBoundary < earliest {
                self.olderBoundary = nil
                historyExhausted = false
            }
        } catch {
            if !Task.isCancelled, generation == displayGeneration { recentFailure = AppErrorMessage(error) }
        }
    }

    public func loadOlder() async {
        guard !Task.isCancelled, !isRefreshing, !isLoadingHistory, canLoadOlder, let boundary = historyBoundary else { return }
        let generation = displayGeneration
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let page = try await service.history(before: boundary)
            guard generation == displayGeneration else { return }
            rows = Self.merge(page.items, rows, cap: 5_000)
            olderBoundary = page.items.first?.dbId ?? boundary
            historyExhausted = !page.hasMore
            historyFailure = nil
        } catch {
            if !Task.isCancelled, generation == displayGeneration { historyFailure = AppErrorMessage(error) }
        }
    }

    private static func merge(_ first: [GuestLogEntry], _ second: [GuestLogEntry], cap: Int) -> [GuestLogEntry] {
        var persisted = Set<Int64>()
        let unique = (first + second).filter { row in
            guard let databaseID = row.dbId else { return true }
            return persisted.insert(databaseID).inserted
        }
        return Array(unique.suffix(cap))
    }
}
