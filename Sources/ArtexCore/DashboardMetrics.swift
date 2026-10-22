import Foundation

public enum DashboardTokenSource: String, CaseIterable, Sendable { case old, ledger }
public enum DashboardProfileSelection: Hashable, Sendable { case all, profile(Int64?) }
public struct DashboardTokenBucket: Equatable, Sendable {
    public var input: Double = 0
    public var output: Double = 0
    public var cacheRead: Double = 0
    public var cacheWrite: Double = 0
    public var taskCount: Int64 = 0
    public var total: Double { input + output }
    mutating func add(_ tokens: DashboardTokenCounts, tasks: Int64 = 0) throws {
        try tokens.validate()
        let (nextCount, overflow) = taskCount.addingReportingOverflow(tasks)
        guard tasks >= 0, !overflow else { throw BackendAPIError.invalidResponse }
        input += tokens.inputTokens; output += tokens.outputTokens
        cacheRead += tokens.cacheReadTokens; cacheWrite += tokens.cacheWriteTokens; taskCount = nextCount
        guard [input, output, cacheRead, cacheWrite, total].allSatisfy(\.isFinite) else { throw BackendAPIError.invalidResponse }
    }
}
public struct DashboardDay: Identifiable, Sendable {
    public let date: String
    public let input: Double
    public let output: Double
    public let cacheRead: Double
    public var id: String { date }
    public var label: String { String(date.suffix(5)) }
}
public struct DashboardCount: Identifiable, Sendable {
    public let name: String
    public let count: Int64
    public var id: String { name }
}
public struct DashboardTrafficBucket: Identifiable, Sendable {
    public let status: Int
    public let count: Int
    public var id: Int { status }
}

/// Derived from the pinned browser calculations; the injected clock makes date cutoffs reproducible.
public struct DashboardMetrics: Sendable {
    public static let dayRanges = [7, 30, 90, 180, 365]
    public let tokens: DashboardTokenBucket
    public let daily: [DashboardDay]
    public var uncachedInput: Double { tokens.input - tokens.cacheRead }
    public var cacheHitPercent: Double { tokens.input > 0 ? (tokens.cacheRead / tokens.input * 100).rounded() : 0 }
    public let runningTasks: Int
    public let recentTasks: [DashboardTask]
    public let recentFindings: [DashboardFinding]
    public let recentActivity: [DashboardActivity]
    public let severityCounts: [String: Int]
    public let activityCounts: [String: Int]
    public let assetTotal: Int64
    public let assetTypes: [DashboardCount]
    public let trafficBuckets: [DashboardTrafficBucket]
    public let recentTraffic: [DashboardTraffic]

    public init(snapshot: DashboardSnapshot, source: DashboardTokenSource, selection: DashboardProfileSelection,
                days: Int, now: Date, calendar: Calendar = .current) throws {
        guard Self.dayRanges.contains(days), now.timeIntervalSince1970.isFinite,
              let cutoffDate = calendar.date(byAdding: .day, value: -days, to: now) else { throw BackendAPIError.invalidResponse }
        try snapshot.validate()
        let formatter = ISO8601DateFormatter()
        let cutoff = String(formatter.string(from: cutoffDate).prefix(10))
        let defaultID = try snapshot.slow.profiles.first(where: \.isDefault).map { try LLMWire.numericID($0.id) }
        var nameIDs: [String: Int64] = [:]
        for profile in snapshot.slow.profiles { nameIDs[profile.name] = try LLMWire.numericID(profile.id) }
        func included(_ id: Int64?) -> Bool {
            switch selection { case .all: true; case .profile(let selected): selected == id }
        }
        var total = DashboardTokenBucket()
        var dayValues: [String: DashboardTokenBucket] = [:]
        func addDay(_ date: String, _ counts: DashboardTokenCounts) throws {
            guard date >= cutoff else { return }
            var bucket = dayValues[date] ?? DashboardTokenBucket()
            try bucket.add(counts); dayValues[date] = bucket
        }
        switch source {
        case .old:
            for task in snapshot.tasks where included(task.llmProfileId ?? defaultID) {
                let counts = task.tokens ?? DashboardTokenCounts()
                try total.add(counts, tasks: 1)
                try addDay(String(task.createdAt.prefix(10)), counts)
            }
            for conversation in snapshot.fast.conversations where included(conversation.llmProfileId ?? defaultID) {
                try total.add(conversation.tokens)
                try addDay(String(conversation.createdAt.prefix(10)), conversation.tokens)
            }
        case .ledger:
            for row in snapshot.slow.usage.byProfile where included(nameIDs[row.profileName] ?? defaultID) {
                try total.add(row.tokens, tasks: row.tasks)
            }
            for row in snapshot.slow.usage.daily where included(nameIDs[row.profileName] ?? defaultID) {
                try addDay(row.date, row.tokens)
            }
        }
        // Preserve raw browser chart series: input already includes cached input.
        tokens = total
        daily = dayValues.keys.sorted().map { date in
            let bucket = dayValues[date]!
            return DashboardDay(date: date, input: bucket.input, output: bucket.output, cacheRead: bucket.cacheRead)
        }
        runningTasks = snapshot.tasks.filter { $0.status == "running" }.count
        recentTasks = Array(snapshot.tasks.sorted { $0.activityUnix > $1.activityUnix }.prefix(5))
        func timestamp(_ value: String) -> Double {
            if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: value)?.timeIntervalSince1970 ?? 0
        }
        recentFindings = Array(snapshot.fast.findings.sorted { timestamp($0.ts) > timestamp($1.ts) }.prefix(8))
        let activity = snapshot.fast.activity.filter { $0.kind != "usage" }
        recentActivity = Array(activity.sorted { $0.seq > $1.seq }.prefix(6))
        severityCounts = Dictionary(grouping: snapshot.fast.findings, by: \.severity).mapValues(\.count)
        activityCounts = Dictionary(grouping: activity, by: \.kind).mapValues(\.count)
        // Snapshot validation has already proved that this sum cannot overflow.
        assetTotal = snapshot.slow.assetCounts.values.reduce(0, +)
        var types: [DashboardCount] = []
        for (name, count) in snapshot.slow.assetCounts where count > 0 {
            types.append(DashboardCount(name: name, count: count))
        }
        types.sort { left, right in
            if left.count == right.count { return left.name < right.name }
            return left.count > right.count
        }
        assetTypes = Array(types.prefix(8))
        trafficBuckets = Dictionary(grouping: snapshot.slow.traffic, by: { $0.status / 100 * 100 })
            .map { DashboardTrafficBucket(status: $0.key, count: $0.value.count) }.sorted { $0.status < $1.status }
        recentTraffic = Array(snapshot.slow.traffic.sorted { timestamp($0.ts) > timestamp($1.ts) }.prefix(5))
    }
}
