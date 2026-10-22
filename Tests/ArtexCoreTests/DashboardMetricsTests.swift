import XCTest
@testable import ArtexCore

final class DashboardMetricsTests: XCTestCase {
    private var fixtureURL: URL { Bundle.module.url(forResource: "dashboard-snapshot", withExtension: "json", subdirectory: "Fixtures")! }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")! }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func fixture(_ edit: ((inout [String: Any]) -> Void)? = nil) throws -> DashboardSnapshot {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        edit?(&object)
        return try LLMWire.decode(DashboardSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testOldSourceIncludesConversationsButCountsTasksOnly() throws {
        let data = try fixture()
        let metrics = try DashboardMetrics(snapshot: data, source: .old, selection: .all, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(metrics.tokens.input, 200)
        XCTAssertEqual(metrics.tokens.output, 40)
        XCTAssertEqual(metrics.tokens.cacheRead, 55)
        XCTAssertEqual(metrics.tokens.cacheWrite, 6)
        XCTAssertEqual(metrics.tokens.taskCount, 2)
        XCTAssertEqual(metrics.uncachedInput, 145)
        XCTAssertEqual(metrics.cacheHitPercent, 28)
        let a = try DashboardMetrics(snapshot: data, source: .old, selection: .profile(1), days: 7, now: now, calendar: calendar)
        XCTAssertEqual(a.tokens.input, 130)
        XCTAssertEqual(a.tokens.taskCount, 1)
        XCTAssertEqual(a.daily.map(\.date), ["2026-10-21"])
    }
    func testNewSourceUnmatchedNamesDefaultAndRangeChangesChartOnly() throws {
        let data = try fixture()
        let short = try DashboardMetrics(snapshot: data, source: .ledger, selection: .all, days: 7, now: now, calendar: calendar)
        let long = try DashboardMetrics(snapshot: data, source: .ledger, selection: .all, days: 30, now: now, calendar: calendar)
        XCTAssertEqual(short.tokens.input, 1139)
        XCTAssertEqual(short.tokens.output, 32)
        XCTAssertEqual(short.tokens.taskCount, 4)
        XCTAssertEqual(short.tokens, long.tokens)
        XCTAssertEqual(short.daily.count, 3)
        XCTAssertEqual(long.daily.count, 4)
        let a = try DashboardMetrics(snapshot: data, source: .ledger, selection: .profile(1), days: 7, now: now, calendar: calendar)
        XCTAssertEqual(a.tokens.input, 1089)
        XCTAssertEqual(a.tokens.taskCount, 3)
        XCTAssertEqual(a.daily.map(\.date), ["2026-10-21", "2026-10-22"])
        XCTAssertEqual(a.daily.first?.input, 80) // Raw browser chart input already includes cache.
        XCTAssertEqual(a.daily.first?.cacheRead, 20)
    }
    func testMissingDefaultAndDuplicateProfileNamesDoNotLoseAllBucket() throws {
        let noDefault = try fixture { object in
            var slow = object["slow"] as! [String: Any]; var profiles = slow["profiles"] as! [[String: Any]]
            profiles[0]["is_default"] = false; slow["profiles"] = profiles; object["slow"] = slow
        }
        let unassigned = try DashboardMetrics(snapshot: noDefault, source: .ledger, selection: .profile(nil), days: 7, now: now, calendar: calendar)
        XCTAssertEqual(unassigned.tokens.input, 10)
        let all = try DashboardMetrics(snapshot: noDefault, source: .ledger, selection: .all, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(all.tokens.input, 1139)
        let duplicate = try fixture { object in
            var slow = object["slow"] as! [String: Any]; var profiles = slow["profiles"] as! [[String: Any]]
            var extra = profiles[0]; extra["id"] = "3"; extra["is_default"] = false
            profiles.append(extra); slow["profiles"] = profiles; object["slow"] = slow
        }
        let lastName = try DashboardMetrics(snapshot: duplicate, source: .ledger, selection: .profile(3), days: 7, now: now, calendar: calendar)
        XCTAssertEqual(lastName.tokens.input, 1079)
    }
    func testVisibleSortingCountsAndDistributionsMatchBrowser() throws {
        let metrics = try DashboardMetrics(snapshot: fixture(), source: .old, selection: .all, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(metrics.runningTasks, 1)
        XCTAssertEqual(metrics.recentTasks.map(\.id), ["1", "2"])
        XCTAssertEqual(metrics.recentFindings.map(\.id), ["f2", "f1"])
        XCTAssertEqual(metrics.recentActivity.map(\.seq), [4, 2, 1])
        XCTAssertEqual(metrics.severityCounts["high"], 1)
        XCTAssertEqual(metrics.assetTotal, 8)
        XCTAssertEqual(metrics.assetTypes.map(\.name), ["endpoint", "ip"])
        XCTAssertEqual(metrics.trafficBuckets.map(\.status), [200, 400, 500])
        XCTAssertEqual(metrics.trafficBuckets.map(\.count), [2, 1, 1])
        XCTAssertEqual(metrics.recentTraffic.map(\.id), ["4", "3", "2", "1"])
    }
    func testInvalidMetricsAndOverflowFailWithoutHostTrap() throws {
        let invalid = try fixture { object in
            var slow = object["slow"] as! [String: Any]
            slow["asset_counts"] = ["a": Int64.max, "b": Int64.max]; object["slow"] = slow
        }
        XCTAssertThrowsError(try DashboardMetrics(snapshot: invalid, source: .old, selection: .all, days: 7, now: now, calendar: calendar))
        XCTAssertThrowsError(try DashboardMetrics(snapshot: fixture(), source: .old, selection: .all, days: -1, now: now, calendar: calendar))
        XCTAssertThrowsError(try DashboardTokenCounts(inputTokens: .infinity).validate())
        XCTAssertThrowsError(try DashboardTokenCounts(inputTokens: -1).validate())
        XCTAssertThrowsError(try DashboardTokenCounts(inputTokens: 0.5).validate())
    }
    func testCalendarDayCutoffUsesLocalDSTBeforeUTCDatePrefix() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = ISO8601DateFormatter().date(from: "2026-11-02T00:30:00Z")!
        let data = try fixture { object in
            var tasks = object["tasks"] as! [[String: Any]]
            tasks[0]["created_at"] = "2026-10-25T00:00:00Z"
            tasks[1]["created_at"] = "2026-10-24T23:59:59Z"
            object["tasks"] = tasks
            var fast = object["fast"] as! [String: Any]; fast["conversations"] = []; object["fast"] = fast
        }
        let result = try DashboardMetrics(snapshot: data, source: .old, selection: .all, days: 7, now: instant, calendar: local)
        XCTAssertEqual(result.daily.map(\.date), ["2026-10-25"])
        XCTAssertEqual(result.tokens.input, 150) // Totals are independent of the chart cutoff.
    }
    func testEmptySnapshotAndTruncationLimits() throws {
        let empty = try fixture { object in
            object["tasks"] = []
            var fast = object["fast"] as! [String: Any]
            for key in ["findings", "activity", "pending", "conversations"] { fast[key] = [] }
            object["fast"] = fast
            var slow = object["slow"] as! [String: Any]
            slow["profiles"] = []; slow["asset_counts"] = [:]; slow["traffic"] = []
            slow["usage"] = ["by_profile": [], "daily": []]; object["slow"] = slow
        }
        let metrics = try DashboardMetrics(snapshot: empty, source: .ledger, selection: .all, days: 30, now: now, calendar: calendar)
        XCTAssertEqual(metrics.tokens.total, 0); XCTAssertEqual(metrics.cacheHitPercent, 0)
        XCTAssertTrue(metrics.daily.isEmpty); XCTAssertTrue(metrics.recentActivity.isEmpty)
        let full = try fixture { object in
            let task = (object["tasks"] as! [[String: Any]])[0]
            object["tasks"] = (0..<12).map { i in var t = task; t["id"] = String(i); t["last_activity_unix"] = i; return t }
            var fast = object["fast"] as! [String: Any]
            let finding = (fast["findings"] as! [[String: Any]])[0]
            fast["findings"] = (0..<12).map { i in var f = finding; f["id"] = String(i); return f }
            let activity = (fast["activity"] as! [[String: Any]])[0]
            fast["activity"] = (0..<12).map { i in var a = activity; a["seq"] = i; return a }; object["fast"] = fast
        }
        let limited = try DashboardMetrics(snapshot: full, source: .old, selection: .all, days: 7, now: now, calendar: calendar)
        XCTAssertEqual(limited.recentTasks.map(\.id), ["11", "10", "9", "8", "7"])
        XCTAssertEqual(limited.recentFindings.count, 8)
        XCTAssertEqual(limited.recentActivity.map(\.seq), [11, 10, 9, 8, 7, 6])
    }

}
