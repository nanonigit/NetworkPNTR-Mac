import XCTest
@testable import ArtexCore

final class FindingPollingTests: XCTestCase {
    @MainActor func testViewPollingSingleFlightFiveSecondsAndOldCleanupCannotStopNewLoop() async throws {
        let api = FindingStateAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []; var durations: [Duration] = []
        let model = FindingStore(service:FindingService(client:api),sleep:{ d in durations.append(d);try await withCheckedThrowingContinuation{sleeps.append($0)} })
        api.replies = [FST.page(["7"])]; let old = Task{await model.runView()}; try await FST.reached{sleeps.count == 1}
        await model.runView(); XCTAssertEqual(api.calls.count,1); XCTAssertTrue(model.isPolling)
        model.stop(); api.replies = [FST.page(["8"])]; let new = Task{await model.runView()}; try await FST.reached{sleeps.count == 2}
        sleeps[0].resume(); await old.value; XCTAssertTrue(model.isPolling)
        model.stop(); sleeps[1].resume(); await new.value; XCTAssertFalse(model.isPolling); XCTAssertEqual(durations,[.seconds(5),.seconds(5)])
    }
    @MainActor func testAssetViewSnapshotEndsViewPollingButIndependentStatsKeepsRunning() async throws {
        let api = FindingStateAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []
        let model = FindingStore(service:FindingService(client:api),sleep:{_ in try await withCheckedThrowingContinuation{sleeps.append($0)} })
        XCTAssertTrue(model.setView(.asset)); api.replies = [FST.tree,FST.page(["7"])]; await model.runView()
        XCTAssertFalse(model.isPolling); XCTAssertTrue(sleeps.isEmpty); XCTAssertEqual(api.calls.count,2)
        api.replies = [FST.stats]; let stats = Task{await model.runStats()}; try await FST.reached{sleeps.count == 1}
        XCTAssertTrue(model.isStatsPolling); await model.runStats(); XCTAssertEqual(api.calls.count,3)
        model.stop(); sleeps[0].resume(); await stats.value; XCTAssertFalse(model.isStatsPolling); XCTAssertEqual(model.stats.value?.total,2)
    }
    @MainActor func testSwitchToAssetWhileSleepingFetchesExactlyOneNewSnapshot() async throws {
        let api = FindingStateAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []
        let model = FindingStore(service:FindingService(client:api),sleep:{_ in try await withCheckedThrowingContinuation{sleeps.append($0)} })
        api.replies = [FST.page(["7"])]; let loop = Task{await model.runView()}; try await FST.reached{sleeps.count == 1}
        XCTAssertTrue(model.setView(.asset)); api.replies = [FST.tree,FST.page(["8"])]; sleeps[0].resume(); await loop.value
        XCTAssertEqual(sleeps.count,1); XCTAssertEqual(api.calls.filter{$0.path.contains("asset-tree")}.count,1); XCTAssertFalse(model.isPolling)
    }
    @MainActor func testStatsOldLoopCannotClearReplacementAndSleepFailureTerminates() async throws {
        let api = FindingStateAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []
        let model = FindingStore(service:FindingService(client:api),sleep:{_ in try await withCheckedThrowingContinuation{sleeps.append($0)} })
        api.replies = [FST.stats]; let old = Task{await model.runStats()}; try await FST.reached{sleeps.count == 1}
        model.reset(); api.replies = [FST.stats]; let new = Task{await model.runStats()}; try await FST.reached{sleeps.count == 2}
        sleeps[0].resume(); await old.value; XCTAssertTrue(model.isStatsPolling)
        model.stop(); sleeps[1].resume(); await new.value; XCTAssertFalse(model.isStatsPolling)
        let failing = FindingStore(service:FindingService(client:api),sleep:{_ in throw CancellationError()})
        api.replies = [FST.page([])]; await failing.runView(); XCTAssertFalse(failing.isPolling)
        api.replies = [FST.stats]; await failing.runStats(); XCTAssertFalse(failing.isStatsPolling)
    }
}

extension FindingPollingTests {
    @MainActor func testAssetResumeWaitsForHeldMutationBeforeItsInitialSnapshot() async throws {
        let api = FindingStateAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []
        let model = FindingStore(service:FindingService(client:api),sleep:{_ in try await withCheckedThrowingContinuation{sleeps.append($0)}})
        XCTAssertTrue(model.setView(.asset)); api.replies = [FST.tree,FST.page(["7"])]; await model.refreshView()
        let target = try FST.record(); api.hold = true
        let write = Task {await model.update(target,patch:.init(name:"changed"),owner:model.viewOwner)}; try await FST.reached{api.held.count == 1}
        model.stop(); var started = false
        let view = Task {started = true;await model.runView()}
        try await FST.reached{started && (!model.isPolling || sleeps.count == 1)}
        XCTAssertTrue(model.isPolling); XCTAssertEqual(sleeps.count,1); XCTAssertEqual(api.calls.count,3)
        api.hold = false; api.replies = [FST.tree,FST.page(["8"])]; api.held[0].resume(returning:FST.reply(FST.row(name:"changed"))); _ = await write.value
        if let pause = sleeps.first {pause.resume()}; await view.value
        XCTAssertEqual(api.calls.count,5); XCTAssertEqual(model.flat.read.value?.items.first?.id,"8"); XCTAssertFalse(model.isPolling)
    }
}
