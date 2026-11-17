import XCTest
@testable import NetworkPNTRCore

final class FindingStoreTests: XCTestCase {
    @MainActor func testCrossPageSelectionAndFilterResetsAreOwnedAndByteExact() async throws {
        let api = FindingStateAPI(), store = FindingStore(service:FindingService(client:FindingStateAPI()))
        XCTAssertEqual(store.view,.flat); XCTAssertEqual(store.flat.size,20); XCTAssertEqual(store.groups.size,10)
        let model = FindingStore(service:FindingService(client:api)); api.replies = [FST.page(["7","8"])]; await model.refreshView()
        let owner = model.viewOwner; model.setSelected("7",selected:true,owner:owner); model.setSelected("999",selected:true,owner:owner)
        XCTAssertEqual(model.selectedIDs,["7"]); XCTAssertTrue(model.configureFlat(page:2,size:20))
        model.setSelected("8",selected:true,owner:owner); XCTAssertEqual(model.selectedIDs,["7"])
        api.replies = [FST.page(["9"],page:2)]; await model.refreshView(); model.setAllVisible(selected:true,owner:model.viewOwner)
        XCTAssertEqual(model.selectedIDs,["7","9"])
        XCTAssertTrue(model.configureFilters(.init(search:"é"))); XCTAssertEqual(model.flat.page,1); XCTAssertNil(model.flat.read.value)
        XCTAssertEqual(model.selectedIDs,["7","9"]); let first = model.viewOwner
        XCTAssertTrue(model.configureFilters(.init(search:"e\u{301}"))); XCTAssertNotEqual(model.viewOwner,first)
        XCTAssertFalse(model.configureFilters(.init(task:"../wrong"))); XCTAssertFalse(model.configureFlat(page:0,size:20))
        model.clearSelection(); XCTAssertTrue(model.selectedIDs.isEmpty)
    }
    @MainActor func testLateFlatResponsesAndOldCycleCannotLaunchNewViewReads() async throws {
        let api = FindingStateAPI(); api.hold = true; let model = FindingStore(service:FindingService(client:api))
        let old = Task { await model.refreshView() }; try await FST.reached{api.held.count == 1}
        XCTAssertTrue(model.setView(.grouped)); let new = Task {await model.refreshView()}; try await FST.reached{api.held.count == 2}
        api.held[0].resume(returning:FST.page(["7"])); _ = await old.value
        XCTAssertNil(model.flat.read.value); XCTAssertTrue(model.groups.read.isLoading); XCTAssertEqual(api.calls.count,2)
        api.held[1].resume(returning:FST.groups(["11"])); _ = await new.value; XCTAssertEqual(model.groups.read.value?.items.count,1)
    }
    @MainActor func testExpandedGroupsKeepIndependentCursorsAndPollOnlyVisibleLoadedGroups() async throws {
        let api = FindingStateAPI(); let model = FindingStore(service:FindingService(client:api)); XCTAssertTrue(model.setView(.grouped))
        api.replies = [FST.groups(["11","__unassigned__"])]; await model.refreshView()
        api.replies = [FST.page(["7"],size:10)]; await model.setGroupExpanded("11",expanded:true,owner:model.viewOwner)
        api.replies = [FST.page(["8"],size:10)]; await model.setGroupExpanded("__unassigned__",expanded:true,owner:model.viewOwner)
        XCTAssertTrue(model.configureGroup("11",page:3,size:10,owner:model.viewOwner)); api.replies = [FST.page(["9"],page:3,size:10)]; await model.refreshGroup("11")
        XCTAssertEqual(model.groupPages["11"]?.page,3); XCTAssertEqual(model.groupPages["__unassigned__"]?.page,1)
        XCTAssertTrue(api.calls.last!.path.contains("task_id=11")); XCTAssertFalse(model.configureGroup("999",page:2,size:10,owner:model.viewOwner))
        api.replies = [FST.groups(["__unassigned__"]),FST.page(["8"],size:10)]; let start = api.calls.count; await model.refreshView()
        XCTAssertEqual(api.calls.count,start+2); XCTAssertTrue(api.calls.last!.path.contains("__unassigned__"))
        XCTAssertEqual(model.groupPages["11"]?.read.value?.items.first?.id,"9")
    }
    @MainActor func testAssetScopeUsesRawKeysAndTreeReadDoesNotReceiveScope() async throws {
        let api = FindingStateAPI(); let model = FindingStore(service:FindingService(client:api)); XCTAssertTrue(model.setView(.asset))
        api.replies = [FST.tree,FST.page(["7"])]; await model.refreshView(); XCTAssertEqual(api.calls.count,2)
        XCTAssertTrue(model.selectAsset("r:é",owner:model.viewOwner)); let owner = model.viewOwner
        XCTAssertTrue(model.selectAsset("r:e\u{301}",owner:owner)); XCTAssertNotEqual(model.viewOwner,owner); XCTAssertEqual(model.flat.page,1)
        api.replies = [FST.page(["8"])]; await model.refreshView(); XCTAssertEqual(api.calls.count,3); XCTAssertTrue(api.calls[2].path.contains("asset_scope")); XCTAssertFalse(model.tree.isStale)
        XCTAssertFalse(model.selectAsset("r:missing",owner:model.viewOwner))
        XCTAssertTrue(model.configureFilters(.init(status:.fixed))); XCTAssertNil(model.assetScope); XCTAssertNil(model.tree.value)
    }
    @MainActor func testStaleReadsStatsAndDetailKeepOwnedLastGoodAndDiscardOldContext() async throws {
        let api = FindingStateAPI(); let model = FindingStore(service:FindingService(client:api))
        api.replies = [FST.page(["7"]),FST.stats]; await model.refreshView(); await model.refreshStats()
        api.replies = [FST.reply(status:503),FST.reply(status:503)]; await model.refreshView(); await model.refreshStats()
        XCTAssertTrue(model.flat.read.isStale); XCTAssertEqual(model.flat.read.value?.items.first?.id,"7"); XCTAssertNotNil(model.stats.failure); XCTAssertEqual(model.stats.value?.total,2)
        api.replies = [FST.reply(FST.row())]; await model.select(id:"7",owner:model.viewOwner); XCTAssertEqual(model.detail.value?.id,"7")
        api.hold = true; let old = Task {await model.refreshSelected()}; try await FST.reached{api.held.count == 1}
        let new = Task {await model.select(id:"8",contextTaskID:"11",owner:model.viewOwner)}; try await FST.reached{api.held.count == 2}
        api.held[0].resume(returning:FST.reply(FST.row())); _ = await old.value; XCTAssertTrue(model.detail.isLoading); XCTAssertNil(model.detail.value)
        api.held[1].resume(returning:FST.reply(FST.row("8"))); _ = await new.value; XCTAssertEqual(model.detail.value?.id,"8")
        let stats = model.stats.value; XCTAssertTrue(model.configureFilters(.init(search:"new"))); XCTAssertEqual(model.stats.value?.total,stats?.total); XCTAssertNil(model.selectedDetail)
    }
    @MainActor func testStopResetAndCancelledReadsDoNotLeakOldValuesOrSelections() async throws {
        let api = FindingStateAPI(); api.hold = true; let model = FindingStore(service:FindingService(client:api)); let session = model.sessionOwner
        let old = Task{await model.refreshView()}; try await FST.reached{api.held.count == 1}; model.stop()
        api.held[0].resume(returning:FST.page(["7"])); _ = await old.value; XCTAssertNil(model.flat.read.value)
        let next = Task{await model.refreshStats()}; try await FST.reached{api.held.count == 2}; model.reset()
        api.held[1].resume(returning:FST.stats); await next.value; XCTAssertNil(model.stats.value); XCTAssertNotEqual(session,model.sessionOwner)
        let cancelled = Task{await model.refreshView()}; try await FST.reached{api.held.count == 3}; cancelled.cancel()
        api.held[2].resume(returning:FST.page(["9"])); _ = await cancelled.value; XCTAssertNil(model.flat.read.value); XCTAssertFalse(model.flat.read.isLoading)
    }
}

extension FindingStoreTests {
    @MainActor func testWholeTableStatsRemainOwnedAcrossViewFilterAndCursorChanges() async throws {
        let api = FindingStateAPI(); api.hold = true; let model = FindingStore(service:FindingService(client:api))
        let stats = Task { await model.refreshStats() }; try await FST.reached{api.held.count == 1}
        XCTAssertTrue(model.configureFilters(.init(search:"new filter"))); XCTAssertTrue(model.setView(.grouped)); XCTAssertTrue(model.configureGroups(page:2,size:10))
        api.held[0].resume(returning:FST.stats); await stats.value
        XCTAssertEqual(model.stats.value?.total,2); XCTAssertFalse(model.stats.isStale); XCTAssertFalse(model.stats.isLoading)
    }
}

extension FindingStoreTests {
    @MainActor func testPrecancelledGroupConfigurationPreservesItsCursorAndCache() async throws {
        let api = FindingStateAPI()
        let store = FindingStore(service:FindingService(client:api)); XCTAssertTrue(store.setView(.grouped))
        api.replies = [FST.groups(["11"])]; await store.refreshView()
        api.replies = [FST.page(["7"],size:10)]; await store.setGroupExpanded("11",expanded:true,owner:store.viewOwner)
        let cancelled = Task { withUnsafeCurrentTask{$0?.cancel()}; return store.configureGroup("11",page:2,size:20,owner:store.viewOwner) }
        let accepted = await cancelled.value; XCTAssertFalse(accepted)
        XCTAssertEqual(store.groupPages["11"]?.page,1); XCTAssertEqual(store.groupPages["11"]?.read.value?.items.first?.id,"7")
    }
}

extension FindingStoreTests {
    @MainActor func testAssetScopeAndFlatCursorDoNotReloadIndependentTreeSnapshot() async throws {
        let api = FindingStateAPI(); let model = FindingStore(service:FindingService(client:api)); XCTAssertTrue(model.setView(.asset))
        api.replies = [FST.tree,FST.page(["7"])]; await model.refreshView(); XCTAssertEqual(api.calls.count,2)
        XCTAssertTrue(model.selectAsset("r:é",owner:model.viewOwner)); api.replies = [FST.page(["8"])]; await model.refreshView()
        XCTAssertEqual(api.calls.count,3); XCTAssertEqual(model.flat.read.value?.items.first?.id,"8"); XCTAssertNil(model.tree.failure); XCTAssertFalse(model.tree.isStale)
        XCTAssertTrue(model.configureFlat(page:2,size:20)); api.replies = [FST.page(["9"],page:2)]; await model.refreshView()
        XCTAssertEqual(api.calls.count,4); XCTAssertEqual(api.calls.filter{$0.path.contains("asset-tree")}.count,1)
        XCTAssertEqual(model.flat.read.value?.items.first?.id,"9")
    }
}

extension FindingStoreTests {
    @MainActor func testHeldTreeSurvivesScopeCursorChangeAndExplicitRefreshCanReloadIt() async throws {
        let api = FindingStateAPI(); let model = FindingStore(service:FindingService(client:api)); XCTAssertTrue(model.setView(.asset))
        api.replies = [FST.tree,FST.page(["7"])]; await model.refreshView()
        api.hold = true; let old = Task{await model.refreshView(forceTree:true)}; try await FST.reached{api.held.count == 1}
        XCTAssertTrue(model.selectAsset("r:é",owner:model.viewOwner)); XCTAssertTrue(model.configureFlat(page:2,size:20)); XCTAssertTrue(model.tree.isLoading)
        api.hold = false; api.replies = [FST.page(["9"],page:2)]; await model.refreshView()
        XCTAssertEqual(api.calls.count,4); XCTAssertEqual(model.flat.read.value?.items.first?.id,"9"); XCTAssertTrue(model.tree.isLoading)
        api.held[0].resume(returning:FST.tree); _ = await old.value
        XCTAssertEqual(api.calls.count,4); XCTAssertFalse(model.tree.isLoading); XCTAssertFalse(model.tree.isStale); XCTAssertEqual(model.tree.value?.nodes.count,2)
        api.replies = [FST.tree,FST.page(["9"],page:2)]; await model.refreshView(forceTree:true)
        XCTAssertEqual(api.calls.count,6); XCTAssertEqual(api.calls.filter{$0.path.contains("asset-tree")}.count,3)
    }
}
