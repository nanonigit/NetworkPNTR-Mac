import XCTest
@testable import NetworkPNTRCore

@MainActor private final class DashboardFixtureTransport: BackendJSONTransport {
    var calls: [String] = []
    var statuses: [String: Int] = [:]
    var overrides: [String: Any] = [:]
    var heldTask: CheckedContinuation<BackendHTTPResponse, any Error>?
    var holdTasks = false
    let fixture: [String: Any]
    init() throws {
        let url = Bundle.module.url(forResource: "dashboard-snapshot", withExtension: "json", subdirectory: "Fixtures")!
        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(method, "GET"); XCTAssertNil(body); XCTAssertNil(bearer)
        calls.append(path)
        if holdTasks && path == "/api/tasks" {
            return try await withCheckedThrowingContinuation { heldTask = $0 }
        }
        let fast = fixture["fast"] as! [String: Any], slow = fixture["slow"] as! [String: Any]
        let objects: [String: Any] = [
            "/api/tasks": ["tasks": fixture["tasks"]!], "/api/exploration/findings": fast["findings"]!,
            "/api/stats": fast["stats"]!, "/api/settings": fast["settings"]!,
            "/api/intercept/pending": ["pending": fast["pending"]!],
            "/api/exploration/activity?limit=30": ["items": fast["activity"]!],
            "/api/tokens/conversations": fast["conversations"]!,
            "/api/traffic?page=0&size=50": ["exchanges": slow["traffic"]!],
            "/api/assets/counts": slow["asset_counts"]!,
            "/api/llm/profiles": ["profiles": slow["profiles"]!],
            "/api/tokens/usage?days=365": slow["usage"]!
        ]
        guard let object = overrides[path] ?? objects[path] else { throw BackendAPIError.invalidResponse }
        return BackendHTTPResponse(status: statuses[path] ?? 200,
                                   body: try JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed))
    }
}
final class DashboardServiceTests: XCTestCase {
    @MainActor func testExactVisibleRoutesDecodeAndValidate() async throws {
        let api = try DashboardFixtureTransport(), service = DashboardService(client: api)
        let tasks = try await service.tasks(), fast = try await service.fast(), slow = try await service.slow()
        XCTAssertEqual(tasks.count, 2); XCTAssertEqual(fast.findings.count, 2); XCTAssertEqual(slow.traffic.count, 4)
        XCTAssertEqual(api.calls.count, 11)
        XCTAssertEqual(Set(api.calls).count, 11)
        XCTAssertTrue(api.calls.contains("/api/tokens/usage?days=365"))
        XCTAssertFalse(api.calls.contains { $0.contains("mcp") })
    }
    @MainActor func testNullSlicesAreEmptyButMissingMalformedAndHTTPFailuresFail() async throws {
        let api = try DashboardFixtureTransport(), service = DashboardService(client: api)
        api.overrides["/api/tasks"] = ["tasks": NSNull()]
        let empty = try await service.tasks(); XCTAssertTrue(empty.isEmpty)
        for malformed: Any in [[:], ["tasks": "wrong"], ["tasks": [["id": "only-id"]]]] {
            api.overrides["/api/tasks"] = malformed
            do { _ = try await service.tasks(); XCTFail("Malformed contract must fail") } catch {}
        }
        api.overrides["/api/tasks"] = ["tasks": []]
        for status in [401, 503] {
            api.statuses["/api/tasks"] = status
            do { _ = try await service.tasks(); XCTFail("HTTP failure must propagate") } catch {}
        }
        api.statuses = [:]
        let row: [String: Any] = ["profile_name": "fixture", "tasks": Int64.max, "input_tokens": 1, "output_tokens": 0, "cache_read_tokens": 0, "cache_write_tokens": 0]
        api.overrides["/api/tokens/usage?days=365"] = ["by_profile": [row, row], "daily": []]
        do { _ = try await service.slow(); XCTFail("Overflowing aggregate must not enter the store") } catch {}
        api.overrides["/api/tokens/usage?days=365"] = ["by_profile": NSNull(), "daily": NSNull()]
        let slow = try await service.slow(); XCTAssertTrue(slow.usage.daily.isEmpty)
        api.overrides["/api/assets/counts"] = ["bad": -1]
        do { _ = try await service.slow(); XCTFail("Invalid metrics must not enter the store") } catch {}
    }
    @MainActor func testStoreRetainsSuccessfulGroupsAndMarksFailedGroupStale() async throws {
        let api = try DashboardFixtureTransport(), store = DashboardStore(service: DashboardService(client: api))
        await store.refreshAll()
        XCTAssertEqual(store.tasks.value?.count, 2); XCTAssertNotNil(store.fast.value); XCTAssertNotNil(store.slow.value)
        api.statuses["/api/tasks"] = 503
        await store.refreshAll()
        XCTAssertEqual(store.tasks.value?.count, 2); XCTAssertNotNil(store.tasks.error)
        XCTAssertNil(store.fast.error); XCTAssertNil(store.slow.error)
        api.statuses = [:]; await store.refreshTasks(); XCTAssertNil(store.tasks.error)
    }
    @MainActor func testHeavyTasksDoNotBlockOtherGroupsAndLateCompletionIsIgnored() async throws {
        let api = try DashboardFixtureTransport(), store = DashboardStore(service: DashboardService(client: api))
        api.holdTasks = true
        let held = Task { await store.refreshTasks() }
        while api.heldTask == nil { await Task.yield() }
        await store.refreshTasks() // No overlapping request while the first task group is held.
        await store.refreshFast(); await store.refreshSlow()
        XCTAssertNotNil(store.fast.value); XCTAssertNotNil(store.slow.value); XCTAssertNil(store.tasks.value)
        XCTAssertEqual(api.calls.filter { $0 == "/api/tasks" }.count, 1)
        store.stop()
        api.heldTask?.resume(returning: BackendHTTPResponse(status: 200, body: Data("{\"tasks\":[]}".utf8)))
        await held.value
        XCTAssertNil(store.tasks.value); XCTAssertFalse(store.tasks.isLoading)
    }
    @MainActor func testCancelledReadClearsLoadingAndOldGenerationCannotOverwriteNewData() async throws {
        let api = try DashboardFixtureTransport(), store = DashboardStore(service: DashboardService(client: api))
        api.holdTasks = true
        let cancelled = Task { await store.refreshTasks() }
        while api.heldTask == nil { await Task.yield() }
        cancelled.cancel()
        api.heldTask?.resume(returning: BackendHTTPResponse(status: 200, body: Data("{\"tasks\":[]}".utf8)))
        await cancelled.value
        XCTAssertFalse(store.tasks.isLoading); XCTAssertNil(store.tasks.error); XCTAssertNil(store.tasks.value)
        api.heldTask = nil
        let old = Task { await store.refreshTasks() }
        while api.heldTask == nil { await Task.yield() }
        let oldResponse = api.heldTask
        store.stop(); api.holdTasks = false
        await store.refreshTasks()
        XCTAssertEqual(store.tasks.value?.count, 2)
        oldResponse?.resume(returning: BackendHTTPResponse(status: 200, body: Data("{\"tasks\":[]}".utf8)))
        await old.value
        XCTAssertEqual(store.tasks.value?.count, 2)
    }

}
