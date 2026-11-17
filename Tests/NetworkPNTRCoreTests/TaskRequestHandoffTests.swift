import XCTest
@testable import NetworkPNTRCore

@MainActor final class TaskRequestHandoffTests: XCTestCase {
    func testThrowingValidatorNeverMarksOrDispatches() async throws {
        let api=ChatTestTransport(),service=TaskCategoryService(client:api)
        for cancellation in [false,true] {
            let handoff=TaskRequestHandoff {
                if cancellation {throw CancellationError()}
                throw BackendAPIError.invalidResponse
            }
            do {_ = try await service.create(name:"synthetic",handoff:handoff);XCTFail("validator ignored")}catch {}
            XCTAssertFalse(handoff.wasDispatched);XCTAssertTrue(api.calls.isEmpty)
        }
    }
    func testSingleUseMarkerRejectsSecondRequestBeforeTransport() async throws {
        let api=ChatTestTransport(),service=TaskCategoryService(client:api);var checks=0
        try api.enqueue(["deleted":8]);try api.enqueue(["deleted":8])
        let handoff=TaskRequestHandoff {checks += 1}
        let first=try await service.delete(id:8,handoff:handoff);XCTAssertEqual(first,8);XCTAssertTrue(handoff.wasDispatched)
        do {_ = try await service.delete(id:8,handoff:handoff);XCTFail("marker reused")}catch BackendAPIError.invalidResponse {}catch {XCTFail("wrong reuse error")}
        XCTAssertEqual(api.calls.count,1);XCTAssertEqual(checks,1)
    }
    func testCancellationInsideValidatorIsCheckedBeforeHandoff() async {
        let api=ChatTestTransport(),service=TaskCategoryService(client:api)
        let handoff=TaskRequestHandoff {withUnsafeCurrentTask{$0?.cancel()}}
        let task=Task {try await service.delete(id:8,handoff:handoff)}
        do {_ = try await task.value;XCTFail("cancellation ignored")}catch is CancellationError {}catch {XCTFail("wrong cancellation")}
        XCTAssertFalse(handoff.wasDispatched);XCTAssertTrue(api.calls.isEmpty)
    }
}
