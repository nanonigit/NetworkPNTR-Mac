import XCTest
import Observation
@testable import ArtexCore

@MainActor private final class ReadAcquisitionProbe {
    var calls = 0
    var next: Task<Bool, Never>?
}

@MainActor final class FindingReadAcquisitionTests: XCTestCase {
    func testSynchronousInvalidationBeforeFirstSuspensionDoesNotStartOrLeaveBusy() async {
        let state = FindingReadState<Int>(), probe = ReadAcquisitionProbe()
        withObservationTracking { _ = state.isLoading } onChange: { MainActor.assumeIsolated { state.invalidate(clear: true) } }
        let accepted = await state.refresh { probe.calls += 1; return 7 }
        XCTAssertFalse(accepted); XCTAssertEqual(probe.calls, 0)
        XCTAssertFalse(state.isLoading); XCTAssertNil(state.value); XCTAssertNil(state.failure)
    }
    func testInvalidationCanQueueFreshReadWithoutOldGateOrCleanupBlockingIt() async throws {
        let state = FindingReadState<Int>(), probe = ReadAcquisitionProbe()
        withObservationTracking { _ = state.isLoading } onChange: {
            MainActor.assumeIsolated {
                state.invalidate(clear: true)
                probe.next = Task { await state.refresh { 9 } }
            }
        }
        let old = await state.refresh { probe.calls += 1; return 7 }
        XCTAssertFalse(old)
        let current = try XCTUnwrap(probe.next)
        let accepted = await current.value
        XCTAssertTrue(accepted); XCTAssertEqual(state.value, 9); XCTAssertFalse(state.isLoading)
        XCTAssertEqual(probe.calls, 0)
    }
}
