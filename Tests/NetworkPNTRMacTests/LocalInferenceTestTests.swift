import NetworkPNTRCore
import Foundation
import Observation
import XCTest
@testable import NetworkPNTRMac

final class LocalInferenceTestTests: XCTestCase {
    @MainActor func testCancellationAtBusyPublicationDoesNotDispatchInference() async throws {
        let test = LocalInferenceTest()
        test.request()
        let attempt = Task { @MainActor in
            withObservationTracking {
                _ = test.isRunning
            } onChange: {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return await test.runPending {
                XCTFail("Canceled request dispatched")
                return try self.reply()
            }
        }
        let completed = await attempt.value
        XCTAssertFalse(completed)
        XCTAssertFalse(test.isRunning)
        XCTAssertNil(test.metrics)
    }

    @MainActor private func reply() throws -> OllamaTextReply {
        try JSONDecoder().decode(OllamaTextReply.self, from: Data(
            #"{"model":"fixture","message":{"role":"assistant","content":"OK"},"done":true,"eval_count":2,"eval_duration":100000000}"#.utf8
        ))
    }

    @MainActor func testTaskReappearanceDoesNotRepeatInference() async throws {
        let test = LocalInferenceTest()
        var calls = 0
        let reply = try reply()
        let idle = await test.runPending { calls += 1; return reply }
        XCTAssertFalse(idle)
        test.request()
        let completed = await test.runPending { calls += 1; return reply }
        XCTAssertTrue(completed)
        XCTAssertEqual(test.metrics?.outputTokens, 2)
        let reappeared = await test.runPending { calls += 1; return reply }
        XCTAssertFalse(reappeared)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(test.isRunning)
        test.request()
        _ = await test.runPending { calls += 1; return reply }
        XCTAssertEqual(calls, 2)
    }

    @MainActor func testCancellationClearsBusyAndRequiresAnotherExplicitRequest() async throws {
        let test = LocalInferenceTest()
        test.request()
        let attempt = Task { @MainActor in
            await test.runPending {
                try await Task.sleep(for: .seconds(30))
                return try self.reply()
            }
        }
        defer { attempt.cancel() }
        for _ in 0..<1_000 {
            if test.isRunning { break }
            await Task.yield()
        }
        XCTAssertTrue(test.isRunning)
        attempt.cancel()
        let completed = await attempt.value
        XCTAssertFalse(completed)
        XCTAssertFalse(test.isRunning)
        XCTAssertNil(test.metrics)
        XCTAssertNil(test.failure)
        let replay = await test.runPending { XCTFail("Canceled request replayed"); return try self.reply() }
        XCTAssertFalse(replay)
        test.request()
        let retry = await test.runPending { try self.reply() }
        XCTAssertTrue(retry)
    }
}
