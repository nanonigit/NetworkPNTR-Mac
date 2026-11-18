#if DEBUG
import XCTest
import Foundation
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

final class NativeReviewPlanTests: XCTestCase {
    func testToolRunsRequireAnIndependentNoProviderReview() throws {
        let flag = "--tool-runs-review"
        XCTAssertThrowsError(try NativeReviewPlan(arguments: [flag]))
        XCTAssertThrowsError(try NativeReviewPlan(arguments: ["--native-review", flag]))
        let args = ["--native-review", "--no-llm-review", flag]
        XCTAssertTrue(try NativeReviewPlan(arguments: args).toolRuns)
        let fault = "--tool-runs-failure-review"
        XCTAssertThrowsError(try NativeReviewPlan(arguments: [fault]))
        XCTAssertFalse(try NativeReviewPlan(arguments: args).toolRunFailure)
        XCTAssertTrue(try NativeReviewPlan(arguments: args + [fault]).toolRunFailure)
        let cancellation = "--tool-runs-cancellation-review"
        XCTAssertThrowsError(try NativeReviewPlan(arguments: [cancellation]))
        XCTAssertTrue(try NativeReviewPlan(arguments: args + [cancellation]).toolRunCancellation)
        XCTAssertThrowsError(try NativeReviewPlan(arguments: args + [cancellation, fault]))
        XCTAssertThrowsError(try NativeReviewPlan(arguments: args + ["--dashboard-diagnostics"]))
    }

    @MainActor final class Client: BackendJSONTransport {
        struct Call { let method: String; let path: String }
        var calls: [Call] = []
        var replies: [BackendHTTPResponse] = []
        func enqueue(_ object: [String: Any], status: Int = 200) throws {
            replies.append(BackendHTTPResponse(status: status, body: try JSONSerialization.data(withJSONObject: object)))
        }
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            calls.append(Call(method: method, path: path))
            guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }
            return replies.removeFirst()
        }
    }
    func testStandardAndExplicitUnconfiguredModes() throws {
        XCTAssertFalse(try NativeReviewPlan(arguments: []).noLLM)
        XCTAssertFalse(try NativeReviewPlan(arguments: ["--native-review"]).noLLM)
        XCTAssertTrue(try NativeReviewPlan(arguments: ["--native-review", "--no-llm-review"]).noLLM)
        XCTAssertThrowsError(try NativeReviewPlan(arguments: ["--no-llm-review"]))
        let skillFlag = "--skill-visibility-diagnostics"
        XCTAssertTrue(try NativeReviewPlan(arguments: [skillFlag]).skillVisibility)
        XCTAssertTrue(try NativeReviewPlan(arguments: [skillFlag]).noLLM)
        XCTAssertThrowsError(try NativeReviewPlan(arguments: ["--native-review", skillFlag]))
        for flag in NativeReviewPlan.seedingFlags {
            XCTAssertThrowsError(try NativeReviewPlan(arguments: [flag, skillFlag]))
            XCTAssertThrowsError(try NativeReviewPlan(arguments: ["--native-review", "--no-llm-review", flag]))
            XCTAssertFalse(try NativeReviewPlan(arguments: [flag]).noLLM)
        }
    }
    func testMCPTaskReviewRequiresIndependentNoLLMReview() throws {
        let flag = "--mcp-task-review"
        XCTAssertTrue(try NativeReviewPlan(arguments: [flag, "--native-review", "--no-llm-review"]).mcpTaskReview)
        for arguments in [[flag], [flag, "--native-review"], [flag, "--no-llm-review"],
                          [flag, "--native-review", "--no-llm-review", "--tool-runs-review"],
                          [flag, "--native-review", "--no-llm-review", "--skill-visibility-diagnostics"]] {
            XCTAssertThrowsError(try NativeReviewPlan(arguments: arguments))
        }
        for seed in NativeReviewPlan.seedingFlags {
            XCTAssertThrowsError(try NativeReviewPlan(arguments: [flag, "--native-review", "--no-llm-review", seed]))
        }
        XCTAssertFalse(try NativeReviewPlan(arguments: ["--native-review", "--no-llm-review"]).mcpTaskReview)
    }
    @MainActor func testEmptyProfilesRequiredWithoutMutation() async throws {
        let client = Client()
        try client.enqueue(["profiles": []])
        try await NativeReviewPlan.requireNoLLM(client: client)
        XCTAssertEqual(client.calls.count, 1)
        XCTAssertEqual(client.calls[0].method, "GET")
        XCTAssertEqual(client.calls[0].path, "/api/llm/profiles")
        try client.enqueue(["profiles": [["id":"fixture", "name":"existing", "format":"openai", "model":"fixture", "is_default":false, "rate_per_second":0, "rate_per_minute":0]]])
        do {
            try await NativeReviewPlan.requireNoLLM(client: client)
            XCTFail("Configured profile accepted")
        } catch { guard case RuntimeError.integrity = error else { return XCTFail("Wrong configured-profile failure") } }
        try client.enqueue(["error":"private"], status:503)
        do {
            try await NativeReviewPlan.requireNoLLM(client: client)
            XCTFail("Failed profile read accepted")
        } catch { }
        XCTAssertTrue(client.calls.allSatisfy { $0.method == "GET" })
    }
}
#endif
