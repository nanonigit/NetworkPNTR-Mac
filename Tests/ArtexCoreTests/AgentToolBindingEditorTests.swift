import Foundation
import XCTest
@testable import ArtexCore

final class AgentToolBindingEditorTests: XCTestCase {
    @MainActor func testAssignmentSendsOnlyDesiredMembershipAndReadsBack() async throws {
        let api = ChatTestTransport()
        let editor = AgentToolBindingEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(["tools": [["key": "record_fact", "enabled": false, "agents": ["other"]]]])
        try api.enqueue(["traffic_capture": false])
        await editor.load()
        let tool = try XCTUnwrap(editor.tools.first)
        XCTAssertTrue(editor.canSet(tool))
        XCTAssertFalse(editor.contains(tool))

        try api.enqueue(["agent": "worker", "tool": "record_fact", "bound": true])
        try api.enqueue(["tools": [["key": "record_fact", "enabled": false, "agents": ["other", "worker"]]]])
        await editor.set("record_fact", bound: true)
        XCTAssertTrue(editor.contains(try XCTUnwrap(editor.tools.first)))
        XCTAssertNil(editor.failure)
        XCTAssertEqual(api.calls.map(\.path), ["/api/tools", "/api/settings",
                                             "/api/agents/worker/tool-bindings/record_fact", "/api/tools"])
        XCTAssertEqual(api.calls[2].method, "PUT")
        XCTAssertEqual(api.calls[2].body, Data("true".utf8))
    }

    @MainActor func testCaptureGateAndUnknownToolCannotWrite() async throws {
        let api = ChatTestTransport()
        let editor = AgentToolBindingEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(["tools": [["key": "traffic_get", "enabled": true, "agents": ["worker"]],
                                    ["key": "traffic_search", "enabled": true, "agents": NSNull()]]])
        try api.enqueue(["traffic_capture": false])
        await editor.load()
        XCTAssertTrue(editor.tools.allSatisfy { editor.trafficGated($0) && !editor.canSet($0) })
        await editor.set("traffic_get", bound: false)
        await editor.set("traffic_search", bound: true)
        await editor.set("not_listed", bound: true)
        XCTAssertEqual(api.calls.count, 2)
    }

    @MainActor func testMismatchedReceiptAndReadbackBlockFurtherWrites() async throws {
        for goodReceipt in [false, true] {
            let api = ChatTestTransport()
            let editor = AgentToolBindingEditor(key: "worker", service: AgentCatalogService(client: api))
            let catalog = ["tools": [["key": "record_fact", "enabled": true, "agents": ["other"]]]]
            try api.enqueue(catalog)
            try api.enqueue(["traffic_capture": true])
            await editor.load()
            try api.enqueue(["agent": goodReceipt ? "worker" : "other", "tool": "record_fact", "bound": true])
            if goodReceipt { try api.enqueue(catalog) }
            await editor.set("record_fact", bound: true)
            XCTAssertNotNil(editor.failure)
            await editor.set("record_fact", bound: true)
            XCTAssertEqual(api.calls.count, goodReceipt ? 4 : 3)
        }
    }
}
