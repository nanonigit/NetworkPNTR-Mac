import Foundation
import XCTest
@testable import NetworkPNTRCore

final class ChatMentionInteractionTests: XCTestCase {
    func testTriggerUsesUTF16CaretAndProtectsEmailTokensNewlinesAndIME() throws {
        let text = "😀 inspect @finding tail"
        let caret = "😀 inspect @finding".utf16.count
        let active = try XCTUnwrap(ChatMentionEditing.active(in: text, caret: caret))
        XCTAssertEqual(active.query, "finding"); XCTAssertEqual(active.range.location, 11)
        for value in ["user@example.com", "path/@x", "@[漏洞#9 record]", "@x\nnext", "@x@y", "@" + String(repeating: "x", count: 221)] {
            XCTAssertNil(ChatMentionEditing.active(in: value, caret: value.utf16.count))
        }
        XCTAssertNil(ChatMentionEditing.active(in: "@finding", caret: 8, composing: true))
        XCTAssertNil(ChatMentionEditing.active(in: text, caret: -1))
        XCTAssertNil(ChatMentionEditing.active(in: text, caret: text.utf16.count + 1))
        XCTAssertNotNil(ChatMentionEditing.active(in: "查看@漏洞", caret: 5))
    }
    func testCategoriesAndAliasesMatchPinnedBrowser() {
        XCTAssertEqual(ChatMentionEditing.search("").categories.count, 9)
        XCTAssertEqual(ChatMentionEditing.search("漏").categories, [.finding])
        XCTAssertEqual(ChatMentionEditing.search("漏洞SQL注入").kind, .finding)
        XCTAssertEqual(ChatMentionEditing.search("漏洞SQL注入").query, "SQL注入")
        XCTAssertEqual(ChatMentionEditing.search(" IP 192.0.2.1 ").kind, .ip)
        XCTAssertEqual(ChatMentionEditing.search(" IP 192.0.2.1 ").query, "192.0.2.1")
        XCTAssertNil(ChatMentionEditing.search("acme.com").kind)
        XCTAssertTrue(ChatMentionEditing.search("acme.com").categories.isEmpty)
    }
    func testAliasPrefixPreservesCombiningMarkAfterChineseWireLabel() {
        let input = ChatMentionEditing.search("漏洞\u{0301}SQL")
        XCTAssertEqual(input.kind, .finding)
        XCTAssertEqual(input.query, "\u{0301}SQL")
    }
    func testInsertionPreservesSuffixAndRejectsStaleActiveQuery() throws {
        let text = "😀 @finding untouched"
        let active = try XCTUnwrap(ChatMentionEditing.active(in: text, caret: "😀 @finding".utf16.count))
        let edit = try XCTUnwrap(ChatMentionEditing.replace(in: text, active: active, with: "@[漏洞#9 label] "))
        XCTAssertEqual(edit.text, "😀 @[漏洞#9 label]  untouched")
        XCTAssertEqual(edit.caret, "😀 @[漏洞#9 label] ".utf16.count)
        XCTAssertNil(ChatMentionEditing.replace(in: "😀 @asset untouched", active: active, with: "bad"))
    }
    func testSelectedTokenRemovalKeepsNeighborsAndLargeIDs() throws {
        let text = "a @[漏洞#9007199254740993 one] b @[IP#4 two] c"
        let tokens = ChatMentionEditing.selected(in: text)
        XCTAssertEqual(tokens.count, 2); XCTAssertEqual(tokens[0].id, "9007199254740993")
        let edit = try XCTUnwrap(ChatMentionEditing.remove(tokens[0], from: text))
        XCTAssertEqual(edit.text, "a  b @[IP#4 two] c")
        XCTAssertEqual(ChatMentionEditing.selected(in: edit.text).map(\.id), ["4"])
        XCTAssertNil(ChatMentionEditing.remove(tokens[0], from: "changed"))
    }
    func testEditingAndCategoriesMatchExecutedBrowserHelper() throws {
        struct Active: Decodable { let start: Int; let end: Int; let query: String }
        struct Category: Decodable { let kind: String }
        struct Search: Decodable { let kind: String; let query: String; let categories: [Category] }
        struct Case: Decodable { let value: String; let caret: Int; let active: Active?; let search: Search? }
        struct Reference: Decodable { let cases: [Case] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("evidence/chat/mention-editing-reference.json"))
        let reference = try JSONDecoder().decode(Reference.self, from: data)
        XCTAssertEqual(reference.cases.count, 9)
        for item in reference.cases {
            let actual = ChatMentionEditing.active(in: item.value, caret: item.caret)
            XCTAssertEqual(actual?.query, item.active?.query, item.value)
            XCTAssertEqual(actual?.range.location, item.active?.start, item.value)
            if let expected = item.active { XCTAssertEqual(actual?.range.length, expected.end - expected.start, item.value) }
            if let expected = item.search, let actual {
                let search = ChatMentionEditing.search(actual.query)
                XCTAssertEqual(search.kind?.rawValue ?? "", expected.kind, item.value)
                XCTAssertEqual(search.query, expected.query, item.value)
                XCTAssertEqual(search.categories.map(\.rawValue), expected.categories.map(\.kind), item.value)
            }
        }
    }
    @MainActor func testObsoleteSearchAndCancelCannotRestoreOldResults() async throws {
        let api = ChatTestTransport(); let store = ChatMentionSearchStore(service: ChatMentionService(client: api))
        var held: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.path.contains("q=old") { return try await withCheckedThrowingContinuation { held = $0 } }
            return try ChatTestTransport.response(["items": [["kind":"asset", "id":2, "label":"new", "description":""]]])
        }
        let old = Task { await store.search(query: "old") }
        for _ in 0..<100 where held == nil { await Task.yield() }
        let reply = try XCTUnwrap(held)
        await store.search(query: "new")
        reply.resume(returning: try ChatTestTransport.response(["items": []])); await old.value
        XCTAssertEqual(store.items.map(\.id), [2]); XCTAssertFalse(store.loading)
        held = nil
        let cancelled = Task { await store.search(query: "old") }
        for _ in 0..<100 where held == nil { await Task.yield() }
        let cancelledReply = try XCTUnwrap(held); store.cancel()
        cancelledReply.resume(returning: try ChatTestTransport.response(["items": [["kind":"asset", "id":1, "label":"old", "description":""]]])); await cancelled.value
        XCTAssertTrue(store.items.isEmpty); XCTAssertFalse(store.loading)
    }
    @MainActor func testPageSingleFlightAndObsoletePageCannotCrossSearch() async throws {
        let api = ChatTestTransport(); let store = ChatMentionSearchStore(service: ChatMentionService(client: api))
        try api.enqueue(["items":[], "next_cursor":"next"]); await store.search(query: "old")
        var held: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.path.contains("cursor=next") { return try await withCheckedThrowingContinuation { held = $0 } }
            return try ChatTestTransport.response(["items":[["kind":"asset", "id":9, "label":"new", "description":""]]])
        }
        let page = Task { await store.loadMore() }
        for _ in 0..<100 where held == nil { await Task.yield() }
        let reply = try XCTUnwrap(held); await store.loadMore()
        XCTAssertEqual(api.calls.count, 2)
        await store.search(query: "new")
        reply.resume(returning: try ChatTestTransport.response(["items":[], "next_cursor":"obsolete"])); await page.value
        XCTAssertEqual(store.items.map(\.id), [9]); XCTAssertNil(store.nextCursor); XCTAssertFalse(store.loadingMore)
    }
    @MainActor func testPageFailureRetryDeduplicationAndCursorLoop() async throws {
        let api = ChatTestTransport(); let store = ChatMentionSearchStore(service: ChatMentionService(client: api))
        let one: [String:Any] = ["kind":"asset", "id":1, "label":"one", "description":""]
        let two: [String:Any] = ["kind":"finding", "id":1, "label":"two", "description":""]
        try api.enqueue(["items":[one], "next_cursor":"next"]); await store.search(query: "query")
        try api.enqueue(["error":"private-secret"], status:503); await store.loadMore()
        XCTAssertEqual(store.items.count, 1); XCTAssertEqual(store.nextCursor, "next")
        XCTAssertNotNil(store.pageError); XCTAssertFalse(store.pageError!.contains("private-secret"))
        try api.enqueue(["items":[one,two], "next_cursor":"last"]); await store.loadMore()
        XCTAssertEqual(store.items.map(\.identity), ["asset:1", "finding:1"])
        XCTAssertNil(store.pageError); XCTAssertTrue(api.calls.last!.path.contains("cursor=next"))
        try api.enqueue(["items":[], "next_cursor":"next"]); await store.loadMore()
        XCTAssertNotNil(store.pageError); XCTAssertEqual(store.nextCursor, "last")
        try api.enqueue(["items":[]]); await store.loadMore()
        XCTAssertNil(store.nextCursor); XCTAssertNil(store.pageError)
    }
}
