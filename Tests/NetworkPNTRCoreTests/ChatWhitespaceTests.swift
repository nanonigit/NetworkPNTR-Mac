import Foundation
import XCTest
@testable import NetworkPNTRCore

final class ChatWhitespaceTests: XCTestCase {
    @MainActor func testUnicodeSendWireAndRecoveryMatchPinnedHandler() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("evidence/chat/attachment-send-browser-reference.json"))
        struct Snapshot: Decodable { let draft: String }
        struct TextCase: Decodable { let name: String; let input: String; let final: Snapshot }
        struct TextReference: Decodable { let cases: [TextCase] }
        let textCases = try JSONDecoder().decode(TextReference.self, from: data).cases
        XCTAssertEqual(textCases.first { $0.name == "bom_guard" }?.input.utf8.first, 239)
        let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(reference["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 9)
        for item in cases.dropFirst(4) {
            let name = try XCTUnwrap(item["name"] as? String)
            let api = ChatTestTransport(), store = ChatStore(service: ChatService(client: api))
            try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7)
            let textCase = try XCTUnwrap(textCases.first { $0.name == name })
            store.draft = textCase.input
            let cards = try JSONDecoder().decode([ChatAttachment].self, from: JSONSerialization.data(withJSONObject: item["attachments"] as Any))
            try store.appendAttachments(cards, for: 7)
            var wire: [String: Any]?
            api.handler = { call in
                wire = try JSONSerialization.jsonObject(with: XCTUnwrap(call.body)) as? [String: Any]
                wire?["id"] = 7
                return try ChatTestTransport.response(["error": "fixture"], status: 503)
            }
            let accepted = await store.sendCurrentDraft()
            XCTAssertFalse(accepted, name)
            let expectedWire = item["request"] as Any
            if expectedWire is NSNull { XCTAssertNil(wire, name) }
            else {
                let actual = try XCTUnwrap(wire, name)
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
                               try JSONSerialization.data(withJSONObject: expectedWire, options: [.sortedKeys]), name)
            }
            XCTAssertEqual(Array(store.draft.utf8), Array(textCase.final.draft.utf8), name)
            XCTAssertEqual(store.attachments, cards, name)
            XCTAssertFalse(store.isSending, name)
        }
    }

    @MainActor func testWorkspaceGuardsBeforeLazyCreationUsingBrowserWhitespace() async throws {
        for (input, sends) in [("\u{FEFF}", false), (" \t\r\n", false), ("\u{85}", true), ("\u{200B}", true)] {
            let api = ChatTestTransport(), workspace = ChatWorkspace(client: api)
            workspace.agentKey = "auto"; workspace.transcript.draft = input
            api.handler = { call in
                if call.path == "/api/conversations", call.method == "POST" {
                    return try ChatTestTransport.response(ChatFixture.conversation())
                }
                if call.method == "POST" { return try ChatTestTransport.response(["error": "fixture"], status: 503) }
                if call.path == "/api/conversations" { return try ChatTestTransport.response(["conversations": [ChatFixture.conversation()]]) }
                return try ChatTestTransport.response(ChatFixture.page([], cursor: 0))
            }
            let accepted = await workspace.send()
            XCTAssertFalse(accepted)
            XCTAssertEqual(api.calls.contains { $0.method == "POST" && $0.path == "/api/conversations" }, sends, input.debugDescription)
            XCTAssertEqual(api.calls.contains { $0.method == "POST" && $0.path.hasSuffix("/messages") }, sends, input.debugDescription)
            XCTAssertEqual(Array(workspace.transcript.draft.utf8), Array(input.utf8))
        }
    }

    @MainActor func testServiceGuardUsesBrowserSetWithoutRewritingSuppliedWire() async throws {
        for (input, sends) in [("\u{FEFF}", false), ("\u{85}", true), ("\u{200B}", true), ("  content\n", true)] {
            let api = ChatTestTransport(), service = ChatService(client: api)
            api.handler = { _ in try ChatTestTransport.response(["status": "accepted"], status: 202) }
            do { try await service.send(id: 7, message: input); XCTAssertTrue(sends, input.debugDescription) }
            catch { XCTAssertFalse(sends, input.debugDescription) }
            XCTAssertEqual(api.calls.count, sends ? 1 : 0, input.debugDescription)
            if sends, let body = api.calls.first?.body {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(Array(try XCTUnwrap(object["message"] as? String).utf8), Array(input.utf8))
            }
        }
    }
}
