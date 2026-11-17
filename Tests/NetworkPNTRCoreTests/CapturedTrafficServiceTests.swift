import XCTest
@testable import NetworkPNTRCore

@MainActor private final class CapturedTrafficFixture: BackendJSONTransport {
    var calls: [(String, String)] = []
    var response = BackendHTTPResponse(status: 200, body: Data("{}".utf8))
    var cancelOnReturn = false
    func reply(_ object: [String: Any], status: Int = 200) throws { response = .init(status: status, body: try JSONSerialization.data(withJSONObject: object)) }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(body); XCTAssertNil(bearer); calls.append((method, path))
        if cancelOnReturn { withUnsafeCurrentTask { $0?.cancel() } }
        return response
    }
}

final class CapturedTrafficServiceTests: XCTestCase {
    private func row(_ id: String = "opaque-7") -> [String: Any] {
        ["id": id, "ts": "opaque time", "host": "literal 中文 한국어", "method": "CUSTOM", "url": "https://captured.invalid/a?x=1", "status": 0, "content_type": "", "resp_len": 10]
    }
    private func page(_ rows: [[String: Any]] = [], enabled: Bool = true, number: Int64 = 0, size: Int = 25) -> [String: Any] {
        ["enabled": enabled, "count": 9, "total": 10, "page": number, "size": size, "exchanges": rows]
    }
    // Decode percent bytes independently; Foundation's String decoding can consume a leading UTF8 BOM.
    private func queryBytes(_ path: String) throws -> [String: Data] {
        let components = try XCTUnwrap(URLComponents(string: path))
        let query = try XCTUnwrap(components.percentEncodedQuery)
        var result: [String: Data] = [:]
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(pair.count, 2)
            let raw = Array(pair[1].utf8)
            var decoded = Data(), cursor = 0
            while cursor < raw.count {
                if raw[cursor] == 37 {
                    XCTAssertLessThan(cursor + 2, raw.count)
                    let hex = String(decoding: raw[(cursor + 1)...(cursor + 2)], as: UTF8.self)
                    decoded.append(try XCTUnwrap(UInt8(hex, radix: 16))); cursor += 3
                } else {
                    XCTAssertNotEqual(raw[cursor], 43, "A literal plus would become a space in the Go server")
                    decoded.append(raw[cursor]); cursor += 1
                }
            }
            result[String(pair[0])] = decoded
        }
        return result
    }
    @MainActor func testPickerQueryUsesZeroBasedPagingAndOpaqueEncodedValues() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        var query = CapturedTrafficQuery(); query.host = "\u{feff}e\u{301}+&/# 中文 한국어"; query.keyword = "a+b &x=1#literal"; query.method = .post; query.page = 2
        try api.reply(page([row()], number: 2))
        let result = try await service.list(query)
        XCTAssertEqual(result.page, 2); XCTAssertEqual(result.size, 25); XCTAssertFalse(result.isUnavailable)
        XCTAssertEqual(result.exchanges.first?.method, "CUSTOM"); XCTAssertEqual(result.exchanges.first?.status, 0)
        let request = try XCTUnwrap(api.calls.first)
        XCTAssertEqual(request.0, "GET")
        let url = try XCTUnwrap(URLComponents(string: request.1)); XCTAssertEqual(url.path, "/api/traffic")
        let values = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(try queryBytes(request.1)["host"], Data(query.host.utf8))
        XCTAssertEqual(values["q"], query.keyword); XCTAssertEqual(values["method"], "POST")
        XCTAssertEqual(values["page"], "2"); XCTAssertEqual(values["size"], "25")
    }
    @MainActor func testDisabledCaptureRetainsHistoryAndOnlyExactMissingIndexIsUnavailable() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        try api.reply(page([row()], enabled: false)); let history = try await service.list(.init())
        XCTAssertFalse(history.enabled); XCTAssertFalse(history.isUnavailable); XCTAssertEqual(history.exchanges.count, 1)
        try api.reply(["enabled": false, "exchanges": []]); let absent = try await service.list(.init())
        XCTAssertTrue(absent.isUnavailable); XCTAssertNil(absent.total); XCTAssertNil(absent.page)
    }
    @MainActor func testMalformedPartialNullAndMismatchedPagesCannotBecomeEmptySuccess() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        var bad = [page(number: 1), page(size: 100), ["enabled": true, "exchanges": []], ["enabled": false, "exchanges": NSNull()], ["enabled": false, "count": NSNull(), "exchanges": []], ["enabled": false, "total": 0, "exchanges": []], page([row(), row()])]
        var negative = page(); negative["total"] = -1; bad.append(negative)
        var malformed = row(); malformed["resp_len"] = -1; bad.append(page([malformed]))
        for value in bad {
            try api.reply(value)
            do { _ = try await service.list(.init()); XCTFail("Malformed catalog accepted") } catch {}
        }
    }
    @MainActor func testCanonicalEquivalentIDsKeepDistinctByteIdentitiesAndRawPreviewIsUnchanged() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        try api.reply(page([row("é"), row("e\u{301}")]))
        let result = try await service.list(.init())
        XCTAssertEqual(result.exchanges.count, 2)
        XCTAssertNotEqual(result.exchanges[0].identity, result.exchanges[1].identity)
        let request = "\u{feff}e\u{301}\r\n中文 한국어\u{0}", response = "@blob sha256:literal\r\n"
        try api.reply(["req": request, "resp": response])
        let id = "\u{feff}opaque/%?+=# 中文 한국어"
        let detail = try await service.detail(id: id)
        XCTAssertEqual(Data(detail.request.utf8), Data(request.utf8)); XCTAssertEqual(Data(detail.response.utf8), Data(response.utf8))
        let components = try XCTUnwrap(URLComponents(string: XCTUnwrap(api.calls.last).1))
        XCTAssertEqual(components.path, "/api/traffic/exchange")
        XCTAssertEqual(try queryBytes(XCTUnwrap(api.calls.last).1)["id"], Data(id.utf8))
    }
    @MainActor func testInvalidQueriesAndIDsNeverDispatch() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        var query = CapturedTrafficQuery(); query.page = -1
        var tooBig = CapturedTrafficQuery(); tooBig.page = Int64.max
        var size = CapturedTrafficQuery(); size.size = 501
        var host = CapturedTrafficQuery(); host.host = String(repeating: "界", count: 2731)
        var keyword = CapturedTrafficQuery(); keyword.keyword = String(repeating: "x", count: 8193)
        var encoded = CapturedTrafficQuery(); encoded.host = String(repeating: "界", count: 1000)
        for value in [query, tooBig, size, host, keyword, encoded] {
            do { _ = try await service.list(value); XCTFail("Invalid query accepted") } catch {}
        }
        for id in ["", "bad\r\nheader", String(repeating: "x", count: 8193), String(repeating: "界", count: 1000)] {
            do { _ = try await service.detail(id: id); XCTFail("Invalid ID accepted") } catch {}
        }
        XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testStatusMalformedRawAndFiniteJSONByteBounds() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        for status in [201, 204, 401, 404, 503] {
            try api.reply(["req": "", "resp": ""], status: status)
            do { _ = try await service.detail(id: "opaque"); XCTFail("Status accepted") }
            catch {
                if status >= 300 {
                    guard case BackendAPIError.status(let code) = error else { return XCTFail("Expected typed status") }
                    XCTAssertEqual(code, status)
                } else {
                    guard case BackendAPIError.invalidResponse = error else { return XCTFail("Unexpected success status must be invalid") }
                }
            }
        }
        for value: [String: Any] in [["req": "only request"], ["req": NSNull(), "resp": ""], [:]] {
            try api.reply(value)
            do { _ = try await service.detail(id: "opaque"); XCTFail("Incomplete preview accepted") } catch {}
        }
        let prefix = Data("{\"req\":\"\",\"resp\":\"\"}".utf8)
        var body = prefix + Data(repeating: 0x20, count: 4 * 1024 * 1024 - prefix.count)
        api.response = .init(status: 200, body: body); _ = try await service.detail(id: "opaque")
        body.append(0x20); api.response = .init(status: 200, body: body)
        do { _ = try await service.detail(id: "opaque"); XCTFail("Oversized valid preview accepted") } catch {}
    }
    @MainActor func testCancellationBeforeAndAfterUncooperativeTransport() async throws {
        for after in [false, true] {
            for catalog in [false, true] {
                let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
                api.cancelOnReturn = after
                try api.reply(catalog ? page() : ["req": "", "resp": ""])
                let task = Task { @MainActor in
                    if !after { withUnsafeCurrentTask { $0?.cancel() } }
                    do {
                        if catalog { _ = try await service.list(.init()) } else { _ = try await service.detail(id: "opaque") }
                        XCTFail("Cancelled read succeeded")
                    } catch { XCTAssertTrue(error is CancellationError) }
                }
                await task.value; XCTAssertEqual(api.calls.count, after ? 1 : 0)
            }
        }
    }
}

extension CapturedTrafficServiceTests {
    @MainActor func testEncodedRequestTargetAllowsExactProtocolLimitAndRejectsOneExtraByte() async throws {
        let api = CapturedTrafficFixture(); let service = CapturedTrafficService(client: api)
        var query = CapturedTrafficQuery()
        query.host = String(repeating: "x", count: 8192 - "/api/traffic?page=0&size=25&host=".utf8.count)
        try api.reply(page()); _ = try await service.list(query)
        XCTAssertEqual(api.calls.last?.1.utf8.count, 8192)
        query.host += "x"
        do { _ = try await service.list(query); XCTFail("Oversized query target accepted") } catch {}
        let id = String(repeating: "x", count: 8192 - "/api/traffic/exchange?id=".utf8.count)
        try api.reply(["req": "", "resp": ""]); _ = try await service.detail(id: id)
        XCTAssertEqual(api.calls.last?.1.utf8.count, 8192)
        do { _ = try await service.detail(id: id + "x"); XCTFail("Oversized detail target accepted") } catch {}
        XCTAssertEqual(api.calls.count, 2)
    }
}
