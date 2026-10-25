import Foundation

public enum TaskSortField: String, CaseIterable, Sendable { case id, created, duration, status }

/// Pinned browser semantics, without changing stored task text or numeric precision.
public enum TaskPresentation {
    public static let statuses = ["created", "queued", "running", "paused", "done", "failed", "timeout"]
    public static func controlAction(_ status: String) -> TaskControlAction? {
        switch status { case "created", "queued", "running": .pause; case "paused": .resume; default: nil }
    }
    public static func rows(_ tasks: [TaskRecord], query: String, status: String?, sort: TaskSortField,
                            ascending: Bool, now: Int64) -> [TaskRecord] {
        let query = ChatText.trim(query).lowercased()
        return tasks.filter { item in
            (status == nil || item.status == status) && (query.isEmpty ||
                [item.id, item.name, item.categoryName ?? "", item.description, item.goal].contains { $0.lowercased().contains(query) })
        }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.pinned, a.pinnedAt != b.pinnedAt { return (a.pinnedAt ?? "") > (b.pinnedAt ?? "") }
            let x: Int64; let y: Int64
            switch sort {
            case .id: x = Int64(a.id) ?? 0; y = Int64(b.id) ?? 0
            case .created: x = created(a); y = created(b)
            case .duration: x = duration(a, now: now); y = duration(b, now: now)
            case .status: x = Int64(statuses.firstIndex(of: a.status) ?? 0); y = Int64(statuses.firstIndex(of: b.status) ?? 0)
            }
            if x != y { return ascending ? x < y : x > y }
            return (Int64(a.id) ?? 0) > (Int64(b.id) ?? 0)
        }
    }
    private static func created(_ task: TaskRecord) -> Int64 {
        if task.createdUnix != 0 { return task.createdUnix }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: task.createdAt) ?? ISO8601DateFormatter().date(from: task.createdAt),
              date.timeIntervalSince1970 >= Double(Int64.min), date.timeIntervalSince1970 < Double(Int64.max) else { return 0 }
        return Int64(date.timeIntervalSince1970.rounded(.down))
    }
    public static func duration(_ task: TaskRecord, now: Int64) -> Int64 {
        let start = task.createdUnix
        let end = task.status == "running" ? now : task.completedUnix > 0 ? task.completedUnix : task.lastActivityUnix
        return start > 0 && end > start ? end - start : 0
    }
    public static func tokens(_ task: TaskRecord) -> String {
        let t = task.tokens
        let total = Decimal(t.inputTokens) + Decimal(t.outputTokens) + Decimal(t.cacheReadTokens) + Decimal(t.cacheWriteTokens)
        return NSDecimalNumber(decimal: total).stringValue
    }
    public static func durationText(_ seconds: Int64, language: AppLanguage) -> String {
        let seconds = max(0, seconds)
        let key: AppStringKey; let a: Int64; let b: Int64
        if seconds >= 86400 { key = .taskUIDays; a = seconds / 86400; b = seconds / 3600 % 24 }
        else if seconds >= 3600 { key = .taskUIHours; a = seconds / 3600; b = seconds / 60 % 60 }
        else if seconds >= 60 { key = .taskUIMinutes; a = seconds / 60; b = seconds % 60 }
        else { key = .taskUISeconds; a = seconds; b = 0 }
        return AppStrings.formatted(key, language: language, values: ["a": String(a), "b": String(b)])
    }
}
