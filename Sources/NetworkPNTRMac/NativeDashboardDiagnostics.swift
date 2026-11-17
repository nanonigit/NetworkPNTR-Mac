#if DEBUG
import NetworkPNTRCore
import Foundation

@MainActor enum NativeDashboardDiagnostics {
    static func seed(session: AuthenticationSession, directory: URL) async throws {
        let service = DashboardService(client: AuthenticatedBackendClient(session: session))
        guard try await service.tasks().isEmpty else { throw RuntimeError.integrity("fresh dashboard fixture") }
        // Developer-only fixed source, never accepted from product UI or a guest host RPC.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let code = try String(contentsOf: root.appendingPathComponent("script/dashboard_seed_guest.py"), encoding: .utf8)
        let body = try JSONSerialization.data(withJSONObject: ["kind": "script", "exec": ["code": code, "timeout_ms": 20_000], "params": [:]])
        let response = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: body)
        guard response.status == 200,
              let result = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] else {
            throw RuntimeError.integrity("dashboard seed response envelope")
        }
        guard result["is_error"] as? Bool == false, let output = result["output"] as? String else {
            throw RuntimeError.integrity("dashboard seed tool execution")
        }
        let metadata: [String: Any] = ["output_bytes": output.utf8.count, "output_lines": output.split(separator: "\n").count,
                                       "has_proof_marker": output.contains("fixture_seeded"), "has_traceback": output.contains("Traceback")]
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: directory.appendingPathComponent("dashboard-seed-output-shape.json"))
        guard let data = output.data(using: .utf8), let proof = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              proof["fixture_seeded"] as? Bool == true, proof["linux_guest"] as? Bool == true, proof["uid"] as? Int == 1000 else {
            throw RuntimeError.integrity("dashboard seed proof format")
        }
    }
    static func collect(session: AuthenticationSession, directory: URL) async throws {
        let service = DashboardService(client: AuthenticatedBackendClient(session: session))
        let tasks = try await service.tasks(), fast = try await service.fast(), slow = try await service.slow()
        let snapshot = DashboardSnapshot(tasks: tasks, fast: fast, slow: slow)
        guard tasks.count == 2, fast.findings.count == 2, fast.pending.count == 4,
              slow.assetCounts.values.reduce(0, +) == 3, slow.profiles.count == 2 else { throw RuntimeError.integrity("nonempty dashboard endpoints") }
        try BackendJSONCoding.encode(snapshot).write(to: directory.appendingPathComponent("dashboard-snapshot-vm.json"))
        let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var scenarios: [String: Any] = [:]
        let selections: [(String, DashboardProfileSelection)] = [("all", .all)] + slow.profiles.map { ($0.name, .profile(Int64($0.id))) }
        for source in DashboardTokenSource.allCases {
            for (name, selection) in selections {
                for days in [7, 30] {
                    let m = try DashboardMetrics(snapshot: snapshot, source: source, selection: selection, days: days, now: now, calendar: calendar)
                    scenarios["\(source.rawValue)/\(name)/\(days)"] = [
                        "input": m.tokens.input, "output": m.tokens.output, "cache_read": m.tokens.cacheRead,
                        "cache_write": m.tokens.cacheWrite, "task_count": m.tokens.taskCount,
                        "uncached_input": m.uncachedInput, "cache_hit_percent": m.cacheHitPercent,
                        "daily": m.daily.map { ["date": $0.date, "input": $0.input, "output": $0.output, "cache_read": $0.cacheRead] as [String: Any] }
                    ]
                }
            }
        }
        let m = try DashboardMetrics(snapshot: snapshot, source: .old, selection: .all, days: 30, now: now, calendar: calendar)
        let result: [String: Any] = ["scenarios": scenarios, "running_tasks": m.runningTasks,
                                   "task_ids": m.recentTasks.map(\.id), "finding_ids": m.recentFindings.map(\.id),
                                   "activity_seq": m.recentActivity.map(\.seq), "severity_counts": m.severityCounts,
                                   "asset_total": m.assetTotal, "asset_types": m.assetTypes.map { ["name": $0.name, "count": $0.count] as [String: Any] },
                                   "pending_count": fast.pending.count, "llm_configured": fast.stats.llmConfigured,
                                   "traffic_capture": fast.settings.trafficCapture, "traffic_count": slow.traffic.count]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("dashboard-contract-vm.json"))
    }
}
#endif
