import ArtexCore
import Foundation
import XCTest
@testable import VMProbe

@MainActor final class CloudHistoryProbeTests: XCTestCase {
    func testReplayRequiresOriginalSingleToolPairAndOrderedReplies() throws {
        let first: [[String: Any]] = [
            activity(1, "user", "Read the local VM history fixture"),
            activity(2, "tool_use", "Read", tool: true),
            activity(3, "tool_result", "fixture result", tool: true),
            activity(4, "result", "VM fixture tool result accepted")
        ]
        let resumed = first + [activity(5, "user", "Continue the saved VM history fixture"), activity(6, "result", "VM fixture saved history accepted")]
        let original = try CloudHistoryProbe.verifyHistory(page(first), resumed: false)
        let restored = try CloudHistoryProbe.verifyHistory(page(resumed), resumed: true)
        XCTAssertEqual(original.toolUseSequence, restored.toolUseSequence)
        XCTAssertEqual(original.toolResultSequence, restored.toolResultSequence)
        XCTAssertThrowsError(try CloudHistoryProbe.verifyHistory(page(first), resumed: true))
        var interim = resumed
        interim[5]["kind"] = "text"
        XCTAssertThrowsError(try CloudHistoryProbe.verifyHistory(page(interim), resumed: true))
        XCTAssertThrowsError(try CloudHistoryProbe.verifyHistory(page(resumed + [activity(7, "tool_use", "Read", tool: true)]), resumed: true))
        var reordered = resumed
        reordered[2]["seq"] = 8
        XCTAssertThrowsError(try CloudHistoryProbe.verifyHistory(page(reordered), resumed: true))
        var wrong = resumed
        wrong[2]["tool_use_id"] = "another-call"
        XCTAssertThrowsError(try CloudHistoryProbe.verifyHistory(page(wrong), resumed: true))
    }

    private func activity(_ sequence: Int, _ kind: String, _ summary: String, tool: Bool = false) -> [String: Any] {
        var row: [String: Any] = ["seq": sequence, "worker": "mainagent", "ts": "fixture", "kind": kind, "summary": summary]
        if tool { row["tool"] = "Read"; row["tool_use_id"] = "call-vm-read-witness" }
        return row
    }

    private func page(_ rows: [[String: Any]]) throws -> ChatPage {
        try BackendJSONCoding.decode(ChatPage.self, from: JSONSerialization.data(withJSONObject: ["items": rows, "running": false]))
    }
}
