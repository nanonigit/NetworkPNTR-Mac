import XCTest
@testable import ArtexCore

final class FindingMutationStateTests: XCTestCase {
    @MainActor private func ready(_ api: FindingStateAPI) async -> FindingStore {
        let model = FindingStore(service:FindingService(client:api)); api.replies = [FST.page(["7"])]; await model.refreshView(); return model
    }
    @MainActor func testConfirmedEditAndDeleteUpdateCachedRowsWithoutLosingConfirmationOnReadFailure() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record()
        model.setSelected("7",selected:true,owner:model.viewOwner)
        api.replies = [FST.reply(FST.row())]; await model.select(id:"7",owner:model.viewOwner)
        api.replies = [FST.reply(FST.row(name:"changed e\u{301} 中文 한국어"))]
        let outcome = await model.update(target,patch:.init(name:"changed e\u{301} 中文 한국어"),owner:model.viewOwner)
        guard case .confirmed(.updated(let updated)) = outcome else {return XCTFail("missing edit confirmation")}
        XCTAssertEqual(model.flat.read.value?.items.first?.name,updated.name); XCTAssertEqual(model.detail.value?.name,updated.name)
        XCTAssertTrue(model.flat.read.isStale); XCTAssertFalse(model.isMutating)
        api.replies = [FST.reply(status:503),FST.reply(status:503)]; await model.refreshView()
        XCTAssertNotNil(model.lastConfirmation); XCTAssertNotNil(model.flat.read.failure)
        api.replies = [FST.reply(#"{"deleted":true,"id":7}"#)]
        guard case .confirmed(.deleted) = await model.delete(updated,owner:model.viewOwner) else {return XCTFail("missing delete confirmation")}
        XCTAssertTrue(model.flat.read.value!.items.isEmpty); XCTAssertEqual(model.flat.read.value?.total,99)
        XCTAssertNil(model.detail.value); XCTAssertNil(model.selectedDetail); XCTAssertTrue(model.selectedIDs.isEmpty)
    }
    @MainActor func testEveryPostHandoffFailureIsUnconfirmedAndReadSuccessCannotClearIt() async throws {
        for status in [400,404,409,500,200] {
            let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(), owner = model.viewOwner, session = model.sessionOwner
            api.replies = [FST.reply(#"{"error":"private SQL 한국어"}"#,status:status)]
            guard case .unconfirmed = await model.update(target,patch:.init(name:"new",status:.confirmed),owner:owner) else {return XCTFail("failed compound patch not uncertain")}
            XCTAssertEqual(model.unknownIDs,["7"]); let count = api.calls.count
            guard case .notStarted = await model.delete(target,owner:owner) else {return XCTFail("unknown replay")}
            XCTAssertEqual(api.calls.count,count)
            api.replies = [FST.page(["7"])]; await model.refreshView(); XCTAssertEqual(model.unknownIDs,["7"])
            XCTAssertFalse(model.acknowledgeUnknown("7",owner:UUID(),revision:model.unknownRevision)); XCTAssertFalse(model.acknowledgeUnknown("8",owner:session,revision:model.unknownRevision))
            XCTAssertTrue(model.acknowledgeUnknown("7",owner:session,revision:model.unknownRevision)); XCTAssertTrue(model.unknownIDs.isEmpty)
        }
    }
    @MainActor func testInvalidOrStaleTargetsAndLocalValidationNeverDispatch() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(); let count = api.calls.count
        guard case .notStarted = await model.update(target,patch:.init(name:"new"),owner:UUID()) else {return XCTFail("stale owner")}
        guard case .notStarted = await model.delete(try FST.record("8"),owner:model.viewOwner) else {return XCTFail("foreign target")}
        guard case .notStarted = await model.delete(try FST.record(inherited:true),owner:model.viewOwner) else {return XCTFail("inherited target")}
        guard case .invalidInput = await model.update(target,patch:.init(),owner:model.viewOwner) else {return XCTFail("empty patch")}
        guard case .invalidInput = await model.update(target,patch:.init(name:String(repeating:"x",count:65537)),owner:model.viewOwner) else {return XCTFail("oversized patch")}
        XCTAssertEqual(api.calls.count,count); XCTAssertTrue(model.unknownIDs.isEmpty); XCTAssertFalse(model.isMutating)
        let cancelled = Task {withUnsafeCurrentTask{$0?.cancel()};return await model.delete(target,owner:model.viewOwner)}
        guard case .notStarted = await cancelled.value else {return XCTFail("precancelled write")}; XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testStopKeepsPendingGateAndDiscardsLateSuccessButRetainsUnknownIdentity() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(); api.hold = true
        let work = Task {await model.update(target,patch:.init(name:"changed"),owner:model.viewOwner)}; try await FST.reached{api.held.count == 1}
        XCTAssertTrue(model.isMutating); XCTAssertFalse(model.configureFilters(.init(search:"other")))
        model.stop(); XCTAssertTrue(model.isMutating); await model.refreshView(); XCTAssertEqual(api.calls.count,2)
        guard case .notStarted = await model.delete(target,owner:model.viewOwner) else {return XCTFail("overlapping write")}
        api.held[0].resume(returning:FST.reply(FST.row(name:"changed")))
        guard case .discarded = await work.value else {return XCTFail("late UI receipt")}
        XCTAssertFalse(model.isMutating); XCTAssertEqual(model.unknownIDs,["7"]); XCTAssertNil(model.lastConfirmation)
        XCTAssertEqual(model.flat.read.value?.items.first?.name,target.name)
    }
    @MainActor func testResetDoesNotReleaseOldGateAndCannotLeakCompletionToNewSession() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(); api.hold = true; let oldSession = model.sessionOwner
        let work = Task {await model.delete(target,owner:model.viewOwner)}; try await FST.reached{api.held.count == 1}
        model.reset(); XCTAssertTrue(model.isMutating); XCTAssertNotEqual(oldSession,model.sessionOwner); await model.refreshStats(); XCTAssertEqual(api.calls.count,2)
        api.held[0].resume(returning:FST.reply(#"{"deleted":true,"id":7}"#))
        guard case .discarded = await work.value else {return XCTFail("old session confirmation")}
        XCTAssertFalse(model.isMutating); XCTAssertNil(model.flat.read.value); XCTAssertTrue(model.unknownIDs.isEmpty); XCTAssertNil(model.lastConfirmation)
    }
    @MainActor func testPostDispatchCancellationKeepsUnknownAndDoesNotApplyEvenValidReceipt() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(); api.hold = true
        let work = Task {await model.delete(target,owner:model.viewOwner)}; try await FST.reached{api.held.count == 1}
        work.cancel(); api.held[0].resume(returning:FST.reply(#"{"deleted":true,"id":7}"#))
        guard case .unconfirmed = await work.value else {return XCTFail("cancelled write confirmation")}
        XCTAssertEqual(model.unknownIDs,["7"]); XCTAssertEqual(model.flat.read.value?.items.first?.id,"7"); XCTAssertFalse(model.isMutating)
    }
}

extension FindingMutationStateTests {
    @MainActor func testGlobalEditCannotTurnInheritedContextDetailIntoEditableFinding() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record()
        api.replies = [FST.reply(FST.row(inherited:true))]; await model.select(id:"7",contextTaskID:"99",owner:model.viewOwner)
        XCTAssertTrue(model.detail.value!.inherited); XCTAssertFalse(model.detail.value!.canMutate)
        api.replies = [FST.reply(FST.row(name:"changed"))]
        guard case .confirmed = await model.update(target,patch:.init(name:"changed"),owner:model.viewOwner) else {return XCTFail("global edit failed")}
        XCTAssertEqual(model.flat.read.value?.items.first?.name,"changed"); XCTAssertEqual(model.selectedDetail?.contextTaskID,"99")
        XCTAssertTrue(model.detail.value!.inherited); XCTAssertFalse(model.detail.value!.canMutate); XCTAssertTrue(model.detail.isStale)
        api.replies = [FST.reply(FST.row(name:"changed",inherited:true))]; await model.refreshSelected()
        XCTAssertTrue(model.detail.value!.inherited); XCTAssertFalse(model.detail.value!.canMutate); XCTAssertEqual(model.detail.value?.name,"changed")
    }
    @MainActor func testStaleAcknowledgementCannotClearLaterUncertaintyForSameID() async throws {
        let api = FindingStateAPI(); let model = await ready(api); let target = try FST.record(), session = model.sessionOwner
        api.replies = [FST.reply(status:400)]
        guard case .unconfirmed = await model.update(target,patch:.init(name:"A"),owner:model.viewOwner) else {return XCTFail("missing A")}
        let revisionA = model.unknownRevision
        let acknowledgeA = {model.acknowledgeUnknown("7",owner:session,revision:revisionA)}
        XCTAssertTrue(acknowledgeA())
        api.replies = [FST.reply(status:500)]
        guard case .unconfirmed = await model.update(target,patch:.init(name:"B"),owner:model.viewOwner) else {return XCTFail("missing B")}
        XCTAssertFalse(acknowledgeA()); XCTAssertEqual(model.unknownIDs,["7"])
        XCTAssertTrue(model.acknowledgeUnknown("7",owner:session,revision:model.unknownRevision))
    }
}
