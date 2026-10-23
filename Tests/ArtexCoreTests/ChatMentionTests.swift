import Foundation
import XCTest
@testable import ArtexCore

final class ChatMentionTests: XCTestCase {
    private func item(_ kind: String = "finding", id: Int64 = 9, label: String = "fixture") -> [String: Any] {
        ["kind": kind, "id": id, "label": label, "description": "record description"]
    }
    @MainActor func testSearchPreservesInt64OrderAndOpaqueCursorAndEncodesQuery() async throws {
        let api = ChatTestTransport(); let service = ChatMentionService(client: api)
        try api.enqueue(["items": [item(id: 9_007_199_254_740_993), item("asset", id: 4)], "next_cursor": "opaque_-9"])
        let page = try await service.search(query: "  日本 +&#  ", cursor: "before_-7")
        XCTAssertEqual(page.items.map(\.id), [9_007_199_254_740_993, 4]); XCTAssertEqual(page.nextCursor, "opaque_-9")
        let call = try XCTUnwrap(api.calls.last)
        XCTAssertEqual(call.method, "GET"); XCTAssertNil(call.body)
        let components = try XCTUnwrap(URLComponents(string: call.path))
        XCTAssertEqual(components.path, "/api/chat/mentions")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["kind": "", "q": "日本 +&#", "cursor": "before_-7"])
        XCTAssertTrue(call.path.contains("%2B"))
    }
    @MainActor func testSearchSupportsAllNineCategoriesAndEmptyPages() async throws {
        let api = ChatTestTransport(); let service = ChatMentionService(client: api)
        XCTAssertEqual(ChatMentionKind.allCases.count, 9)
        for kind in ChatMentionKind.allCases {
            try api.enqueue(["items": []])
            let page = try await service.search(kind: kind, query: "")
            XCTAssertTrue(page.items.isEmpty); XCTAssertNil(page.nextCursor)
            XCTAssertTrue(api.calls.last!.path.contains("kind=\(kind.rawValue)"))
        }
    }
    @MainActor func testQueryScalarAndCursorBoundsRejectBeforeTransport() async throws {
        let api = ChatTestTransport(); let service = ChatMentionService(client: api)
        try api.enqueue(["items": []]); _ = try await service.search(query: String(repeating: "😀", count: 200))
        let accepted = api.calls.count
        for (query, cursor) in [(String(repeating: "😀", count: 201), ""), ("", String(repeating: "a", count: 2049)), ("", "bad/+")] {
            do { _ = try await service.search(query: query, cursor: cursor); XCTFail("Invalid input accepted") } catch {}
        }
        XCTAssertEqual(api.calls.count, accepted)
    }
    @MainActor func testMalformedPagesAndErrorsStaySanitized() async throws {
        let api = ChatTestTransport(); let service = ChatMentionService(client: api)
        for object: [String: Any] in [[:], ["items": NSNull()], ["items": [item(id: 0)]], ["items": [item(), item()]], ["items": [], "next_cursor": "bad/+"], ["items": Array(repeating: item(), count: 21)]] {
            try api.enqueue(object)
            do { _ = try await service.search(query: ""); XCTFail("Malformed page accepted") } catch {}
        }
        try api.enqueue(["error": "private-secret-body"], status: 503)
        do { _ = try await service.search(query: ""); XCTFail("HTTP error ignored") }
        catch { XCTAssertFalse(error.localizedDescription.contains("private-secret-body")) }
    }
    func testWireTokensMatchBrowserLabelsSanitizationAndUTF16Truncation() throws {
        let labels = ["finding": "漏洞", "asset": "资产", "company": "企业", "endpoint": "接口", "ip": "IP", "app": "应用", "root_domain": "域名", "subdomain": "子域名", "service": "服务"]
        for (kind, label) in labels {
            let value = try BackendJSONCoding.decode(ChatMention.self, from: JSONSerialization.data(withJSONObject: item(kind, id: 9_007_199_254_740_993, label: "a[part]\n\tname\u{FEFF}end")))
            XCTAssertEqual(value.token, "@[\(label)#9007199254740993 a（part） name end]")
        }
        let unicode = try BackendJSONCoding.decode(ChatMention.self, from: JSONSerialization.data(withJSONObject: item(label: String(repeating: "a", count: 99) + "😀")))
        XCTAssertEqual(unicode.token, "@[漏洞#9 " + String(repeating: "a", count: 99) + "�]")
        let future = try BackendJSONCoding.decode(ChatMention.self, from: JSONSerialization.data(withJSONObject: item("future_record")))
        XCTAssertEqual(future.token, "@[资产#9 fixture]")
    }
}
