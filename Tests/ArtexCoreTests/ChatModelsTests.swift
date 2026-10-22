import XCTest
@testable import ArtexCore

final class ChatModelsTests: XCTestCase {
    private func event(_ seq: Int64, _ kind: String = "text", _ summary: String = "fixture") throws -> ChatActivity {
        try BackendJSONCoding.decode(ChatActivity.self, from: Data("""
        {"seq":\(seq),"worker":"mainagent","ts":"2026-10-23T00:00:00Z","kind":"\(kind)","summary":"\(summary)"}
        """.utf8))
    }
    func testReplayAndOutOfOrderDeltasReplaceBySequenceWithoutDuplicates() throws {
        let old = try [event(3), event(1, "thinking", "old"), event(2)]
        let delta = try [event(4), event(1, "text", "new"), event(3)]
        let merged = ChatTranscript.merge(old, incoming: delta)
        XCTAssertEqual(merged.map(\.seq), [1, 2, 3, 4])
        XCTAssertEqual(merged.first?.summary, "new")
        XCTAssertEqual(ChatTranscript.merge(merged, incoming: delta), merged)
    }
    func testOlderPageMergePreservesNewerSameSequenceData() throws {
        let oldPage = try [event(1), event(2, "text", "old")]
        let current = try [event(2, "text", "new"), event(3)]
        let merged = ChatTranscript.merge(oldPage, incoming: current)
        XCTAssertEqual(merged.map(\.seq), [1, 2, 3])
        XCTAssertEqual(merged[1].summary, "new")
        XCTAssertTrue(ChatTranscript.merge([], incoming: []).isEmpty)
    }
    func testKnownAndFutureKindsKeepTheirWireIdentityAndVisibleContent() throws {
        let kinds = ["tool_use", "tool_result", "text", "thinking", "result", "user", "intent", "round", "usage", "llm_switch", "llm_failover", "intercept_request", "future_event"]
        for (index, kind) in kinds.enumerated() {
            let item = try event(Int64(index + 1), kind, "visible")
            XCTAssertEqual(item.kind, kind)
            XCTAssertEqual(item.summary, "visible")
            XCTAssertEqual(item.id, Int64(index + 1))
        }
    }
    func testActivityPreservesToolPairMetadataAndLargeIntegerWithoutHostInterpretation() throws {
        let data = Data(#"{"seq":8,"worker":"mainagent","ts":"fixture","kind":"tool_result","summary":"visible","detail":"raw guest output","tool":"Shell","tool_use_id":"pair-1","is_error":true,"main_seg":2,"source_task_id":"task-1","inherited":true,"input_tokens":10,"output_tokens":2,"cache_read_tokens":3,"cache_write_tokens":4,"metadata":{"future_key":{"large_id":9007199254740993,"flag":true,"empty":null,"list":["x",1.25]}}}"#.utf8)
        let item = try BackendJSONCoding.decode(ChatActivity.self, from: data)
        XCTAssertEqual(item.toolUseId, "pair-1")
        XCTAssertEqual(item.mainSeg, 2)
        XCTAssertEqual(item.sourceTaskId, "task-1")
        XCTAssertEqual(item.isError, true)
        XCTAssertEqual(item.inherited, true)
        XCTAssertEqual(item.inputTokens, 10)
        XCTAssertEqual(item.outputTokens, 2)
        XCTAssertEqual(item.cacheReadTokens, 3)
        XCTAssertEqual(item.cacheWriteTokens, 4)
        XCTAssertEqual(item.detail, "raw guest output")
        XCTAssertEqual(item.metadata?["future_key"], .object(["large_id": .integer(9_007_199_254_740_993), "flag": .bool(true), "empty": .null, "list": .array([.string("x"), .number(1.25)])]))
        let roundTrip = try BackendJSONCoding.decode(ChatActivity.self, from: BackendJSONCoding.encode(item))
        XCTAssertEqual(roundTrip, item)
    }
    func testPinFallbackRespectsExplicitFalseAndNullableProfile() throws {
        let base = #"{"id":7,"agent_key":"auto","title":"fixture","created_at":"fixture","updated_at":"fixture","llm_profile_id":null"#
        func conversation(_ suffix: String) throws -> ChatConversation {
            try BackendJSONCoding.decode(ChatConversation.self, from: Data((base + suffix + "}").utf8))
        }
        XCTAssertFalse(try conversation("").isPinned)
        XCTAssertTrue(try conversation(#", "pinned_at":"fixture""#).isPinned)
        XCTAssertFalse(try conversation(#", "pinned":false,"pinned_at":"fixture""#).isPinned)
        XCTAssertTrue(try conversation(#", "pinned":true"#).isPinned)
        let item = try conversation("")
        XCTAssertNil(item.llmProfileId)
        XCTAssertFalse(item.isRunning)
    }
    func testRequiredEventShapeCannotSilentlyBecomeAnEmptyTranscript() {
        for data in [Data(#"{"seq":1,"kind":"text"}"#.utf8), Data(#"{"seq":"oops","worker":"x","ts":"x","kind":"text","summary":"x"}"#.utf8)] {
            XCTAssertThrowsError(try BackendJSONCoding.decode(ChatActivity.self, from: data))
        }
    }
}
