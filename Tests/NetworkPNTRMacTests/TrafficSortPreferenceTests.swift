import NetworkPNTRCore
import Foundation
import Observation
import XCTest
@testable import NetworkPNTRMac

@MainActor private final class TrafficSortAPI: BackendJSONTransport {
    var paths: [String] = [], methods: [String] = []
    var holdWrite = false
    var held: CheckedContinuation<BackendHTTPResponse, any Error>?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path); methods.append(method)
        if method != "GET", holdWrite { return try await withCheckedThrowingContinuation { held = $0 } }
        let object: Any
        if path == "/api/traffic/hosts" { object = ["hosts": []] }
        else if path == "/api/settings" { object = ["traffic_capture": true] }
        else {
            let items = URLComponents(string: path)?.queryItems ?? []
            object = ["enabled": true, "count": 0, "total": 0, "page": Int64(items.first { $0.name == "page" }?.value ?? "0") ?? 0, "size": Int(items.first { $0.name == "size" }?.value ?? "50") ?? 50, "exchanges": []] as [String: Any]
        }
        return .init(status: 200, body: try JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor final class TrafficSortPreferenceTests: XCTestCase {
    private let key = "traffic.sort.preference.v1"
    private func suite() throws -> (UserDefaults, String) {
        let name = "artex.traffic-sort.test." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
    private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Missing controlled handoff"); throw CancellationError()
    }
    private func payload(_ preferences: UserDefaults) throws -> [String: String] {
        let data = try XCTUnwrap(preferences.data(forKey: key))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }
    private func model(_ api: TrafficSortAPI, _ preferences: UserDefaults?) -> TrafficScreenModel {
        TrafficScreenModel(store: TrafficStore(service: .init(client: api)), preferences: preferences)
    }
    func testEveryValidPairRestoresBeforeFirstRead() async throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        for field in ["ts", "status", "resp_len"] { for direction in ["asc", "desc"] {
            preferences.set(try JSONSerialization.data(withJSONObject: ["field": field, "direction": direction]), forKey: key)
            let api = TrafficSortAPI(), screen = model(api, preferences); defer { screen.reset() }
            let lease = try XCTUnwrap(screen.begin()); XCTAssertEqual(screen.presentation, lease)
            XCTAssertEqual(screen.store.query.sort.rawValue, field); XCTAssertEqual(screen.store.query.order.rawValue, direction)
            try await reached { api.paths.count == 3 && !screen.store.isRefreshing }
            XCTAssertTrue(api.paths[0].contains("sort=" + field)); XCTAssertTrue(api.paths[0].contains("order=" + direction))
            XCTAssertEqual(screen.store.query.host, ""); XCTAssertEqual(screen.store.query.page, 0); XCTAssertEqual(screen.store.query.size, 50)
        } }
    }
    func testMalformedMissingAndOversizedSettingsFallBackAndCanonicalize() async throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let values: [Any?] = [nil, "legacy", Data("bad".utf8), Data("[]".utf8), Data("{}".utf8), Data(#"{"field":"status","direction":"DESC"}"#.utf8), Data(#"{"field":"unknown","direction":"asc"}"#.utf8), Data(#"{"field":7,"direction":"asc"}"#.utf8), Data(repeating: 32, count: 4097)]
        for value in values {
            preferences.removeObject(forKey: key); if let value { preferences.set(value, forKey: key) }
            let screen = model(TrafficSortAPI(), preferences); defer { screen.reset() }
            _ = try XCTUnwrap(screen.begin())
            XCTAssertEqual(screen.store.query.sort, .timestamp); XCTAssertEqual(screen.store.query.order, .descending)
            XCTAssertEqual(try payload(preferences), ["field": "ts", "direction": "desc"])
        }
    }
    func testUnknownInputKeysNeverSurviveCanonicalStorage() throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(Data(#"{"field":"status","direction":"asc","host":"private","body":"literal","page":7}"#.utf8), forKey: key)
        let screen = model(TrafficSortAPI(), preferences); defer { screen.reset() }
        _ = try XCTUnwrap(screen.begin())
        XCTAssertEqual(try payload(preferences), ["field": "status", "direction": "asc"])
    }
    func testConstructionDoesNotWriteAndNilDisablesStorage() throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let unused = model(TrafficSortAPI(), preferences); defer { unused.reset() }
        XCTAssertNil(preferences.object(forKey: key))
        let screen = model(TrafficSortAPI(), nil); defer { screen.reset() }
        let lease = try XCTUnwrap(screen.begin())
        XCTAssertTrue(screen.control(.sort(.status), lease: lease)); XCTAssertTrue(screen.stop(lease))
        _ = try XCTUnwrap(screen.begin()); XCTAssertEqual(screen.store.query.sort, .timestamp)
        XCTAssertNil(preferences.object(forKey: key))
    }
    func testOnlyAcceptedSortPersistsAndPrivateStateDoesNotReopen() async throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let api = TrafficSortAPI(), screen = model(api, preferences); defer { screen.reset() }
        let lease = try XCTUnwrap(screen.begin()); try await reached { !screen.store.isRefreshing && api.paths.count == 3 }
        XCTAssertTrue(screen.edit(.host, text: "\u{FEFF}e\u{301} 中文 한국어", lease: lease))
        XCTAssertTrue(screen.control(.method(.post), lease: lease))
        XCTAssertEqual(try payload(preferences), ["field": "ts", "direction": "desc"])
        XCTAssertTrue(screen.control(.sort(.responseLength), lease: lease))
        XCTAssertTrue(screen.control(.sort(.responseLength), lease: lease))
        XCTAssertEqual(try payload(preferences), ["field": "resp_len", "direction": "asc"])
        screen.reset()
        let next = model(TrafficSortAPI(), preferences); defer { next.reset() }
        _ = try XCTUnwrap(next.begin())
        XCTAssertEqual(next.store.query.sort, .responseLength); XCTAssertEqual(next.store.query.order, .ascending)
        XCTAssertEqual(next.store.query.host, ""); XCTAssertNil(next.store.query.method); XCTAssertNil(next.store.query.status)
        XCTAssertEqual(Set(preferences.persistentDomain(forName: name)?.keys ?? Dictionary<String, Any>().keys), [key])
    }
    func testModalAndOldLeaseCannotSaveNewSort() async throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let api = TrafficSortAPI(), screen = model(api, preferences); defer { screen.reset() }
        let lease = try XCTUnwrap(screen.begin()); try await reached { api.paths.count == 3 && !screen.store.isRefreshing }
        XCTAssertTrue(screen.prepareDeletion(.purgeAll, lease: lease, owner: screen.store.owner))
        XCTAssertFalse(screen.control(.sort(.status), lease: lease))
        let next = try XCTUnwrap(screen.begin()); XCTAssertNotEqual(next, lease)
        XCTAssertFalse(screen.control(.sort(.responseLength), lease: lease))
        XCTAssertEqual(try payload(preferences), ["field": "ts", "direction": "desc"])
    }
    func testStopDuringSortPublicationDoesNotSaveAbandonedChoice() throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let screen = model(TrafficSortAPI(), preferences); defer { screen.reset() }
        let lease = try XCTUnwrap(screen.begin())
        withObservationTracking { _ = screen.store.query } onChange: { MainActor.assumeIsolated { _ = screen.stop(lease) } }
        XCTAssertFalse(screen.control(.sort(.status), lease: lease))
        XCTAssertEqual(try payload(preferences), ["field": "ts", "direction": "desc"])
        XCTAssertNil(screen.presentation)
    }
    func testResetDuringRestoreSkipsReadAndCanonicalWrite() throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let original = Data(#"{"field":"status","direction":"asc","extra":"untouched-on-abort"}"#.utf8)
        preferences.set(original, forKey: key)
        let api = TrafficSortAPI(), screen = model(api, preferences); defer { screen.reset() }
        screen.store.stop()
        withObservationTracking { _ = screen.store.query } onChange: { MainActor.assumeIsolated { screen.reset() } }
        XCTAssertNil(screen.begin()); XCTAssertNil(screen.presentation); XCTAssertEqual(screen.store.query.sort, .timestamp)
        XCTAssertEqual(preferences.data(forKey: key), original); XCTAssertTrue(api.paths.isEmpty)
    }
    func testHeldWriteDefersRestoreBeforeReadingAndKeepsUnknownGate() async throws {
        let (preferences, name) = try suite(); defer { preferences.removePersistentDomain(forName: name) }
        let api = TrafficSortAPI(), screen = model(api, preferences); defer { screen.reset() }
        let lease = try XCTUnwrap(screen.begin()); try await reached { api.paths.count == 3 && !screen.store.isRefreshing }
        api.holdWrite = true; XCTAssertTrue(screen.prepareDeletion(.purgeAll, lease: lease, owner: screen.store.owner))
        let dialog = try XCTUnwrap(screen.deletionDialog)
        let write = Task { await screen.confirmDeletion(id: dialog.id, lease: lease, owner: dialog.owner) }
        try await reached { api.held != nil }; XCTAssertTrue(screen.stop(lease))
        preferences.set(Data(#"{"field":"status","direction":"asc"}"#.utf8), forKey: key)
        let next = try XCTUnwrap(screen.begin()), count = api.paths.count
        XCTAssertFalse(screen.controlsAvailable); XCTAssertEqual(screen.store.query.sort, .timestamp)
        for _ in 0..<20 { await Task.yield() }; XCTAssertEqual(api.paths.count, count)
        api.held?.resume(returning: .init(status: 503, body: Data())); api.held = nil
        guard case .discarded = await write.value else { return XCTFail("Retired writer") }
        try await reached { screen.store.canAcknowledgeUnknown && screen.controlsAvailable }
        XCTAssertEqual(screen.presentation, next); XCTAssertEqual(screen.store.query.sort, .status); XCTAssertEqual(screen.store.query.order, .ascending)
        XCTAssertTrue(api.paths[count].contains("sort=status")); XCTAssertTrue(api.paths[count].contains("order=asc"))
        XCTAssertTrue(screen.store.hasUnknownOutcome); XCTAssertEqual(api.methods.filter { $0 == "DELETE" }.count, 1)
    }
}
