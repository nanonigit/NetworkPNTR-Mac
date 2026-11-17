import NetworkPNTRCore
import Foundation
import XCTest
@testable import VMProbe

@MainActor private final class StandaloneAPI: BackendJSONTransport {
    private struct Body: Decodable { struct Ref: Decodable { let trafficId: String }; let trafficRefs: [Ref] }
    var calls: [(String, String)] = []
    var candidatesReadOnly = false, candidatesMissing = false, incompleteReceipt = false
    var failPost = false, wrongPage = false
    var boundIDs: [String] = []
    var posts: Int { calls.filter { $0.0 == "POST" }.count }
    func exchange(_ index: Int) -> [String: Any] {
        ["id": "fixture-" + String(index), "ts": String(index), "host": "127.0.0.1", "url": CapturedProbeContract.prefix + String(format: "%02d", index), "method": index % 2 == 0 ? "GET" : "POST", "content_type": "text/plain", "status": 200, "resp_len": index]
    }
    func records() throws -> [CapturedTrafficExchange] {
        try BackendJSONCoding.decode([CapturedTrafficExchange].self, from: JSONSerialization.data(withJSONObject: (0..<29).map(exchange)))
    }
    func finding(_ id: String, readOnly: Bool = false) -> [String: Any] {
        var row: [String: Any] = ["id": id, "finding_id": id, "task_id": "11", "name": "owned fixture", "vulnclass": "CWE-79", "severity": "high", "status": "pending", "summary": "raw", "evidence": "raw", "ts": "raw"]
        if readOnly { row["inherited"] = true; row["source_task_id"] = "11" }; return row
    }
    func summary() -> [String: Any] {
        let ids = incompleteReceipt ? Array(boundIDs.prefix(1)) : boundIDs
        let bindings: [[String: Any]] = ids.enumerated().map { position, id in
            let index = Int(id.dropFirst("fixture-".count)) ?? 0
            return ["id": String(position + 1), "finding_id": "9101", "snapshot_id": "snap" + String(position), "role": "supporting", "note": "", "position": position, "created_at": "raw", "snapshot": ["id": "snap" + String(position), "source_traffic_id": id, "captured_at": 0, "url": CapturedProbeContract.prefix + String(format: "%02d", index), "method": "GET", "content_type": "text/plain", "status": 200, "req_hash": "r", "resp_hash": "s", "req_len": 0, "resp_len": index]]
        }
        return ["finding_id": "9101", "version": boundIDs.isEmpty ? 1 : 2, "report_version": 0, "bindings": bindings]
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append((method, path)); var status = 200
        let object: Any
        let page = Int(URLComponents(string: path)?.queryItems?.first { $0.name == "page" }?.value ?? "0") ?? 0
        if path.hasPrefix("/api/exploration/findings?") {
            object = ["items": page == 1 || candidatesMissing ? [finding("77")] : [finding("9101", readOnly: candidatesReadOnly)], "page": page, "page_size": 20, "total": 21]
        } else if path == "/api/exploration/findings/9101/traffic" {
            if method == "POST" { boundIDs = try BackendJSONCoding.decode(Body.self, from: XCTUnwrap(body)).trafficRefs.map(\.trafficId); if failPost { status = 503 } }
            object = summary()
        } else if path == "/api/traffic/hosts" { object = ["hosts": [["host": "127.0.0.1", "count": 29]]] }
        else if path == "/api/settings" { object = ["traffic_capture": true] }
        else {
            let rows = (0..<29).reversed().map(exchange)
            object = ["enabled": true, "count": 29, "total": 29, "page": wrongPage ? 9 : page, "size": 25, "exchanges": Array(rows.dropFirst(page * 25).prefix(25))]
        }
        return .init(status: status, body: try JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor final class StandaloneTrafficExerciseTests: XCTestCase {
    func testRealServiceShapesCrossPageSelectionCandidatePagingAndSingleBind() async throws {
        let api = StandaloneAPI(), records = try api.records()
        let result = try await StandaloneTrafficExercise.run(client: api, records: records)
        XCTAssertEqual(result.pageCounts, [25, 4]); XCTAssertEqual(result.sourceOrdinals, [3, 4])
        XCTAssertTrue(result.crossPageSelectionChecked); XCTAssertTrue(result.replayBlocked); XCTAssertTrue(result.selectionCleared)
        XCTAssertEqual(api.posts, 1); XCTAssertEqual(api.boundIDs, ["fixture-3", "fixture-4"])
        XCTAssertEqual(result.receipt.bindings.count, 2)
        let candidates = api.calls.filter { $0.1.hasPrefix("/api/exploration/findings?") }
        XCTAssertEqual(candidates.count, 2)
        for (index, call) in candidates.enumerated() {
            let query = URLComponents(string: call.1)?.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "limit" }?.value, "20")
            XCTAssertEqual(query.first { $0.name == "page" }?.value, String(index + 1))
        }
    }
    func testWrongFixtureShapeRefusedBeforeIO() async throws {
        for mode in 0..<3 {
            let api = StandaloneAPI(); var rows = try api.records()
            if mode == 0 { rows.removeLast() }
            else if mode == 1 { rows[28] = rows[0] }
            else { rows.swapAt(0, 1) }
            do { _ = try await StandaloneTrafficExercise.run(client: api, records: rows); XCTFail("Wrong fixture accepted") } catch { }
            XCTAssertTrue(api.calls.isEmpty)
        }
    }
    func testReadOnlyOrMissingCandidateCannotBind() async throws {
        for missing in [false, true] {
            let api = StandaloneAPI(); api.candidatesMissing = missing; api.candidatesReadOnly = !missing
            do { _ = try await StandaloneTrafficExercise.run(client: api, records: api.records()); XCTFail("Unavailable target") } catch { }
            XCTAssertEqual(api.posts, 0)
        }
    }
    func testWrongTrafficEnvelopeDoesNotBind() async throws {
        let api = StandaloneAPI(); api.wrongPage = true
        do { _ = try await StandaloneTrafficExercise.run(client: api, records: api.records()); XCTFail("Wrong page") } catch { }
        XCTAssertEqual(api.posts, 0)
    }
    func testIncompleteOrFailedReceiptCannotReportCompletionOrReplay() async throws {
        for fail in [false, true] {
            let api = StandaloneAPI(); api.failPost = fail; api.incompleteReceipt = !fail
            do { _ = try await StandaloneTrafficExercise.run(client: api, records: api.records()); XCTFail("Unconfirmed receipt") } catch { }
            XCTAssertEqual(api.posts, 1)
        }
    }
}
