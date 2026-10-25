import XCTest
@testable import ArtexCore
final class TaskPresentationTests: XCTestCase {
    private func record(_ id: String, _ changes: [String: Any] = [:]) throws -> TaskRecord {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-contract", withExtension: "json", subdirectory: "Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var item = try XCTUnwrap(root["task"] as? [String: Any]); item["id"] = id; item.merge(changes) { _, new in new }
        return try BackendJSONCoding.decode(TaskRecord.self, from: JSONSerialization.data(withJSONObject: item))
    }
    func testPinnedSortNumericPrecisionFiltersAndTieBreakMatchReference() throws {
        let a = try record("9007199254740993", ["status": "running", "name": "alpha", "pinned": true, "pinned_at": "2026-10-23"])
        let b = try record("9007199254740992", ["status": "paused", "name": "Beta", "category_name": "literal 中文"])
        let c = try record("8", ["status": "running", "name": "gamma", "pinned": true, "pinned_at": "2026-10-24"])
        XCTAssertEqual(TaskPresentation.rows([b,a,c], query: "", status: nil, sort: .id, ascending: true, now: 0).map(\.id), ["8",a.id,b.id])
        XCTAssertEqual(TaskPresentation.rows([a,b], query: " 中文 ", status: nil, sort: .id, ascending: false, now: 0).map(\.id), [b.id])
        XCTAssertTrue(TaskPresentation.rows([a,b], query: "Beta", status: "running", sort: .id, ascending: false, now: 0).isEmpty)
        let unpinned = try record("9007199254740993", ["pinned": false])
        XCTAssertEqual(TaskPresentation.rows([b,unpinned], query: "", status: nil, sort: .created, ascending: true, now: 0).map(\.id), [unpinned.id,b.id])
        XCTAssertEqual(TaskPresentation.controlAction("created"), .pause); XCTAssertEqual(TaskPresentation.controlAction("paused"), .resume)
        for status in ["done","failed","timeout","unknown"] { XCTAssertNil(TaskPresentation.controlAction(status)) }
    }
    func testDurationAndCountersUseExactAndBoundedArithmetic() throws {
        let item = try record("7", ["created_unix": 100, "status": "running"])
        XCTAssertEqual(TaskPresentation.duration(item, now: 165), 65)
        XCTAssertEqual(TaskPresentation.duration(item, now: 90), 0)
        let done = try record("7", ["created_unix": 100, "status": "done", "completed_unix": 160, "last_activity_unix": 150])
        XCTAssertEqual(TaskPresentation.duration(done, now: 999), 60)
        XCTAssertEqual(TaskPresentation.tokens(done), "9007199254741002")
        let overflow = try record("7", ["tokens": ["input_tokens": Int64.max, "output_tokens": Int64.max, "cache_read_tokens": 0, "cache_write_tokens": 0]])
        XCTAssertEqual(TaskPresentation.tokens(overflow), "18446744073709551614")
        XCTAssertEqual(TaskPresentation.durationText(65, language: .english), "1m 5s")
        XCTAssertEqual(TaskPresentation.durationText(65, language: .japanese), "1分 5秒")
    }
    func testTaskCatalogAndFeatureGate() throws {
        for key in AppStringKey.allCases where key.rawValue.hasPrefix("task.ui.") {
            for language in AppLanguage.allCases { XCTAssertNotEqual(AppStrings.text(key, language: language), key.rawValue) }
        }
        XCTAssertEqual(AppStrings.text(.taskUITitle, language: .english), "Tasks")
        XCTAssertEqual(AppStrings.text(.taskUITitle, language: .japanese), "タスク")
        XCTAssertEqual(try FeatureCatalog.load().features.first(where: { $0.id == "tasks" })?.nativeStatus,"in_progress")
    }
    func testLocalizedTokenBreakdownRetainsEachCounterAndOpaqueValues() {
        XCTAssertEqual(AppStrings.formatted(.taskUITokenBreakdown, language: .english, values: ["input":"{read}","read":"3","write":"4","output":"2"]), "Input: {read} · Cache read: 3 · Cache write: 4 · Output: 2")
        XCTAssertEqual(TaskPresentation.durationText(90061, language: .japanese), "1日 1時間")
        XCTAssertEqual(TaskPresentation.durationText(3661, language: .english), "1h 1m")
        XCTAssertEqual(TaskPresentation.durationText(-1, language: .english), "0s")
    }

    func testAllSortBranchesCreatedFallbackAndSearchFields() throws {
        let old = try record("7", ["created_unix": 0, "created_at": "2000-01-01T00:00:00.500Z", "status": "running", "description": "distinct-description"])
        let newer = try record("8", ["created_unix": 0, "created_at": "2020-01-01T00:00:00Z", "status": "paused", "goal": "distinct-goal"])
        let invalid = try record("9", ["created_unix": 0, "created_at": "invalid", "status": "future"])
        XCTAssertEqual(TaskPresentation.rows([newer, old, invalid], query: "", status: nil, sort: .created, ascending: true, now: 0).map(\.id), ["9", "7", "8"])
        XCTAssertEqual(TaskPresentation.rows([newer, old, invalid], query: "", status: nil, sort: .status, ascending: false, now: 0).map(\.id), ["8", "7", "9"])
        XCTAssertEqual(TaskPresentation.rows([old,newer], query: " DISTINCT-GOAL ", status: nil, sort: .duration, ascending: true, now: 0).map(\.id), ["8"])
        XCTAssertEqual(TaskPresentation.rows([old,newer], query: "distinct-description", status: nil, sort: .id, ascending: false, now: 0).map(\.id), ["7"])
        let running = try record("10", ["created_unix": 100, "status": "running"])
        let stopped = try record("11", ["created_unix": 100, "status": "paused", "last_activity_unix": 150])
        XCTAssertEqual(TaskPresentation.rows([running, stopped], query: "", status: nil, sort: .duration, ascending: true, now: 200).map(\.id), ["11", "10"])
        XCTAssertEqual(TaskPresentation.duration(stopped, now: 200), 50)
        XCTAssertEqual(TaskPresentation.controlAction("queued"), .pause); XCTAssertEqual(TaskPresentation.controlAction("running"), .pause)
    }

}
