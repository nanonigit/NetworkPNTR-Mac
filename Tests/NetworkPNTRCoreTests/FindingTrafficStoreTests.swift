import XCTest
import Observation
@testable import NetworkPNTRCore

@MainActor private final class TrafficStoreAPI: BackendJSONTransport {
    struct Call { let method, path: String; let body: Data? }
    var calls: [Call] = []
    var held: [Int:CheckedContinuation<BackendHTTPResponse,any Error>] = [:]
    var immediate: BackendHTTPResponse?
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer);let index=calls.count;calls.append(.init(method:method,path:path,body:body))
        if let immediate { return immediate }
        return try await withCheckedThrowingContinuation {held[index]=$0}
    }
    func reply(_ index: Int,_ value: Any,status: Int = 200) throws {
        let continuation=try XCTUnwrap(held.removeValue(forKey:index))
        continuation.resume(returning:.init(status:status,body:try JSONSerialization.data(withJSONObject:value)))
    }
}
@MainActor final class FindingTrafficStoreTests: XCTestCase {
    private func target(_ id: String = "9101",inherited: Bool = false,legacy: Bool = false) throws -> FindingRecord {
        var row: [String:Any] = ["id":id,"finding_id":id,"task_id":"8101","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"","evidence":"","ts":"2026-10-22"]
        if inherited {row["inherited"]=true;row["source_task_id"]="8101"}
        if legacy {row.removeValue(forKey:"finding_id")}
        return try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:row))
    }
    private func binding(_ id: String = "1",owner: String = "9101") throws -> [String:Any] {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-traffic-contract",withExtension:"json"))
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        var row=try XCTUnwrap(fixture["binding"] as? [String:Any]);row["id"]=id;row["finding_id"]=owner;return row
    }
    private func summary(_ owner: String = "9101",version: Int64 = 2,ids: [String] = ["1","2"]) throws -> [String:Any] {
        ["finding_id":owner,"version":version,"report_version":1,"bindings":try ids.map{try binding($0,owner:owner)}]
    }
    private func page(offset: Int64 = 0,total: Int64 = 9000,next: Int64 = 8192) -> [String:Any] {
        ["content":"literal evidence","offset":offset,"total":total,"next_offset":next,"truncated":next<total,"binary":false]
    }
    private func detail(_ id: String = "1",owner: String = "9101") throws -> [String:Any] {
        ["binding":try binding(id,owner:owner),"request":page(total:0,next:0),"response":page()]
    }
    private func wait(_ api: TrafficStoreAPI,_ count: Int) async throws {
        for _ in 0..<2000 {if api.calls.count>=count {return};await Task.yield()}
        XCTFail("request not dispatched");throw BackendAPIError.invalidResponse
    }
    private func load(_ store: FindingTrafficStore,_ api: TrafficStoreAPI,_ id: String = "9101") async throws {
        XCTAssertTrue(store.select(try target(id)));let index=api.calls.count
        let task=Task {await store.refreshSummary()};try await wait(api,index+1);try api.reply(index,summary(id));await task.value
    }
    func testReverseSummaryAndFailureKeepCurrentOwnershipAndLastGoodValue() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api))
        XCTAssertTrue(store.select(try target()));let old=Task {await store.refreshSummary()};try await wait(api,1)
        let owner=store.owner;XCTAssertTrue(store.select(try target("9102")));XCTAssertNotEqual(store.owner,owner)
        let newer=Task {await store.refreshSummary()};try await wait(api,2)
        try api.reply(1,summary("9102",version:3));await newer.value
        try api.reply(0,summary());await old.value
        XCTAssertEqual(store.summary.value?.findingId,"9102");XCTAssertFalse(store.summary.isLoading)
        let failed=Task {await store.refreshSummary()};try await wait(api,3);try api.reply(2,["error":"private"],status:500);await failed.value
        XCTAssertEqual(store.summary.value?.version,3);XCTAssertTrue(store.summary.isStale);XCTAssertNotNil(store.summary.failure)
        XCTAssertFalse(store.selectBinding("1",owner:owner));XCTAssertTrue(store.selectBinding("1",owner:store.owner))
    }
    func testReverseDetailsAndBodyPagesCannotCrossBindingSideOffsetOrTotals() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        XCTAssertTrue(store.selectBinding("1",owner:store.owner))
        let old=Task {await store.refreshDetail()};try await wait(api,2)
        XCTAssertTrue(store.selectBinding("2",owner:store.owner))
        let current=Task {await store.refreshDetail()};try await wait(api,3)
        try api.reply(2,detail("2"));await current.value;try api.reply(1,detail());await old.value
        XCTAssertEqual(store.detail.value?.binding.id,"2")
        let first=Task {await store.refreshBody()};try await wait(api,4)
        XCTAssertTrue(store.configureBody(side:.response,offset:8192,owner:store.owner))
        let second=Task {await store.refreshBody()};try await wait(api,5)
        try api.reply(4,page(offset:8192,next:9000));await second.value;try api.reply(3,page());await first.value
        XCTAssertEqual(store.body.value?.offset,8192);XCTAssertFalse(store.nextBodyPage(owner:store.owner))
        XCTAssertTrue(store.configureBody(side:.request,offset:0,owner:store.owner))
        let invalid=Task {await store.refreshBody()};try await wait(api,6)
        try api.reply(5,page());await invalid.value
        XCTAssertNil(store.body.value);XCTAssertNotNil(store.body.failure)
        XCTAssertFalse(store.configureBody(side:.request,offset:1,owner:store.owner))
        XCTAssertFalse(store.configureBody(side:.response,offset:-1,owner:store.owner))
        XCTAssertTrue(store.configureBody(side:.response,offset:0,owner:store.owner))
        let initial=Task {await store.refreshBody()};try await wait(api,7);try api.reply(6,page());await initial.value
        XCTAssertTrue(store.nextBodyPage(owner:store.owner));XCTAssertEqual(store.bodyOffset,8192);XCTAssertNil(store.body.value)
    }
    func testInvalidWritesDoNotDispatchAndConfirmedSnapshotSurvivesRefreshFailure() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let invalid=await store.apply(.reorder(["1"]),owner:store.owner)
        guard case .invalidInput=invalid else {return XCTFail("wrong invalid outcome")}
        XCTAssertEqual(api.calls.count,1);XCTAssertTrue(store.unknownIDs.isEmpty)
        let owner=store.owner,task=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)}
        try await wait(api,2);XCTAssertTrue(store.isMutating)
        XCTAssertFalse(store.select(try target("9102")));XCTAssertFalse(store.selectBinding("2",owner:owner))
        guard case .notStarted=await store.apply(.remove(bindingID:"1"),owner:owner) else {return XCTFail("parallel write")}
        await store.refreshSummary();XCTAssertEqual(api.calls.count,2)
        try api.reply(1,summary(version:3,ids:["2"]));let outcome=await task.value
        guard case .confirmed(let result)=outcome else {return XCTFail("confirmation lost")}
        XCTAssertEqual(result.version,3);XCTAssertEqual(store.summary.value?.version,3);XCTAssertFalse(store.summary.isStale)
        XCTAssertEqual(store.lastConfirmation?.version,3);XCTAssertFalse(store.isMutating)
        let refresh=Task {await store.refreshSummary()};try await wait(api,3);try api.reply(2,["error":"private"],status:500);await refresh.value
        XCTAssertEqual(store.lastConfirmation?.version,3);XCTAssertEqual(store.summary.value?.version,3)
        guard case .notStarted=await store.apply(.remove(bindingID:"2"),owner:owner) else {return XCTFail("stale write")}
        XCTAssertEqual(api.calls.count,3)
    }
    func testConflictReadDoesNotAcknowledgeAndCapturedRevisionControlsReplay() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let owner=store.owner,oldRevision=store.unknownRevision
        let task=Task {await store.apply(.remove(bindingID:"1"),owner:owner)};try await wait(api,2)
        try api.reply(1,["error":"private conflict"],status:409)
        guard case .unconfirmed=await task.value else {return XCTFail("conflict replayable")}
        XCTAssertEqual(store.unknownIDs,["9101"]);XCTAssertNotEqual(store.unknownRevision,oldRevision)
        let refresh=Task {await store.refreshSummary()};try await wait(api,3);try api.reply(2,summary(version:4));await refresh.value
        XCTAssertEqual(store.unknownIDs,["9101"])
        guard case .notStarted=await store.apply(.remove(bindingID:"1"),owner:owner) else {return XCTFail("unknown replay")}
        XCTAssertFalse(store.acknowledgeUnknown("9101",owner:owner,revision:oldRevision))
        XCTAssertFalse(store.acknowledgeUnknown("9102",owner:owner,revision:store.unknownRevision))
        XCTAssertTrue(store.acknowledgeUnknown("9101",owner:owner,revision:store.unknownRevision))
        let next=Task {await store.apply(.remove(bindingID:"1"),owner:owner)};try await wait(api,4)
        try api.reply(3,summary(version:5,ids:["2"]));guard case .confirmed=await next.value else {return XCTFail()}
    }
    func testStopKeepsBusyUnknownAndDropsLateSuccessUntilExplicitResumeAcknowledgement() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let owner=store.owner,task=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)};try await wait(api,2)
        store.stop();XCTAssertTrue(store.isMutating);XCTAssertFalse(store.isActive);XCTAssertEqual(store.unknownIDs,["9101"])
        store.resume();XCTAssertNotEqual(store.owner,owner)
        XCTAssertFalse(store.acknowledgeUnknown("9101",owner:store.owner,revision:store.unknownRevision))
        try api.reply(1,summary(version:3,ids:["2"]));guard case .discarded=await task.value else {return XCTFail()}
        XCTAssertFalse(store.isMutating);XCTAssertEqual(store.summary.value?.version,2);XCTAssertNil(store.lastConfirmation)
        let refresh=Task {await store.refreshSummary()};try await wait(api,3);try api.reply(2,summary(version:3,ids:["2"]));await refresh.value
        XCTAssertFalse(store.acknowledgeUnknown("9101",owner:owner,revision:store.unknownRevision))
        XCTAssertTrue(store.acknowledgeUnknown("9101",owner:store.owner,revision:store.unknownRevision))
    }
    func testResetDiscardsOldWriteAndCleanupWithoutChangingNewBusySession() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let old=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)};try await wait(api,2)
        store.reset();XCTAssertNil(store.summary.value);XCTAssertNil(store.selectedBindingID);XCTAssertTrue(store.unknownIDs.isEmpty)
        store.resume();try await load(store,api,"9102")
        let newer=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)};try await wait(api,4)
        try api.reply(1,summary(version:3,ids:["2"]));guard case .discarded=await old.value else {return XCTFail()}
        XCTAssertTrue(store.isMutating);XCTAssertTrue(store.unknownIDs.isEmpty);XCTAssertEqual(store.summary.value?.findingId,"9102")
        try api.reply(3,summary("9102",version:3,ids:["2"]));guard case .confirmed=await newer.value else {return XCTFail()}
        XCTAssertFalse(store.isMutating);XCTAssertEqual(store.lastConfirmation?.findingId,"9102")
    }
    func testInheritedLegacyInvalidSelectionsAndCancelledDispatch() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api))
        XCTAssertFalse(store.select(try target(),contextTaskID:"../1"))
        XCTAssertFalse(store.select(try target(),contextTaskID:"8111"))
        XCTAssertTrue(store.select(try target(legacy:true)));await store.refreshSummary();XCTAssertTrue(api.calls.isEmpty)
        XCTAssertTrue(store.select(try target(inherited:true),contextTaskID:"8111"))
        let read=Task {await store.refreshSummary()};try await wait(api,1);try api.reply(0,summary());await read.value
        guard case .invalidInput=await store.apply(.remove(bindingID:"1"),owner:store.owner) else {return XCTFail()}
        XCTAssertTrue(store.unknownIDs.isEmpty);XCTAssertEqual(api.calls.count,1)
        XCTAssertTrue(store.select(nil));XCTAssertNil(store.summary.value)
        try await load(store,api)
        let cancelled=Task {withUnsafeCurrentTask{$0?.cancel()};return await store.apply(.remove(bindingID:"1"),owner:store.owner)}
        guard case .notStarted=await cancelled.value else {return XCTFail()};XCTAssertTrue(store.unknownIDs.isEmpty)
        let count=api.calls.count,write=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)}
        try await wait(api,count+1);write.cancel();try api.reply(count,summary(version:3))
        guard case .unconfirmed=await write.value else {return XCTFail()};XCTAssertEqual(store.unknownIDs,["9101"])
    }
    func testSummaryReconcilesOnlyOnSuccessAndDetailMustMatchCapturedSnapshot() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        XCTAssertTrue(store.selectBinding("1",owner:store.owner))
        let initial=Task {await store.refreshDetail()};try await wait(api,2);try api.reply(1,detail());await initial.value
        let failed=Task {await store.refreshSummary()};try await wait(api,3);try api.reply(2,["error":"private"],status:500);await failed.value
        XCTAssertEqual(store.selectedBindingID,"1");XCTAssertEqual(store.detail.value?.binding.id,"1")
        let current=Task {await store.refreshSummary()};try await wait(api,4);try api.reply(3,summary(version:3,ids:["2"]));await current.value
        XCTAssertNil(store.selectedBindingID);XCTAssertNil(store.detail.value);XCTAssertNil(store.body.value)
        XCTAssertFalse(store.selectBinding("3",owner:store.owner));XCTAssertTrue(store.selectBinding("2",owner:store.owner))
        var mismatched=try detail("2"),row=try binding("2")
        var snapshot=try XCTUnwrap(row["snapshot"] as? [String:Any]);snapshot["id"]="different-snapshot"
        row["snapshot_id"]="different-snapshot";row["snapshot"]=snapshot;mismatched["binding"]=row
        let wrong=Task {await store.refreshDetail()};try await wait(api,5);try api.reply(4,mismatched);await wrong.value
        XCTAssertNil(store.detail.value);XCTAssertNotNil(store.detail.failure)
        XCTAssertFalse(store.configureBody(side:.response,offset:0,owner:store.owner))
        store.stop();await store.refreshSummary();await store.refreshDetail();await store.refreshBody()
        XCTAssertFalse(store.select(try target("9102")));XCTAssertEqual(api.calls.count,5)
    }
    func testUnknownSurvivesSelectionAndOldOwnersCannotAcknowledgeIt() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let oldOwner=store.owner,write=Task {await store.apply(.remove(bindingID:"1"),owner:store.owner)}
        try await wait(api,2);try api.reply(1,["error":"private"],status:500)
        guard case .unconfirmed=await write.value else {return XCTFail()}
        let revision=store.unknownRevision
        try await load(store,api,"9102");XCTAssertEqual(store.unknownIDs,["9101"]);XCTAssertEqual(store.unknownRevision,revision)
        guard case .notStarted=await store.apply(.remove(bindingID:"1"),owner:store.owner) else {return XCTFail()}
        XCTAssertFalse(store.acknowledgeUnknown("9101",owner:store.owner,revision:revision))
        XCTAssertFalse(store.acknowledgeUnknown("9101",owner:oldOwner,revision:revision))
        try await load(store,api);XCTAssertEqual(store.unknownRevision,revision)
        XCTAssertTrue(store.acknowledgeUnknown("9101",owner:store.owner,revision:revision));XCTAssertTrue(store.unknownIDs.isEmpty)
    }
    func testCancellationBetweenPreparationAndTransportIsNotAnUnknownWrite() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let count=api.calls.count
        let task=Task {
            withObservationTracking { _ = store.isMutating } onChange: { withUnsafeCurrentTask {$0?.cancel()} }
            return await store.apply(.remove(bindingID:"1"),owner:store.owner)
        }
        let outcome=await task.value
        XCTAssertEqual(api.calls.count,count);XCTAssertTrue(store.unknownIDs.isEmpty);XCTAssertFalse(store.isMutating)
        guard case .notStarted=outcome else {return XCTFail("pre-dispatch cancellation marked unknown")}
    }
    func testSynchronousStopAtBusyTransitionDoesNotDispatchOrMarkUnknown() async throws {
        let api=TrafficStoreAPI(),store=FindingTrafficStore(service:.init(client:api));try await load(store,api)
        let count=api.calls.count
        api.immediate = .init(status:200,body:try JSONSerialization.data(withJSONObject:summary(version:3)))
        withObservationTracking { _ = store.isMutating } onChange: { MainActor.assumeIsolated {store.stop()} }
        let outcome=await store.apply(.remove(bindingID:"1"),owner:store.owner)
        XCTAssertEqual(api.calls.count,count);XCTAssertTrue(store.unknownIDs.isEmpty);XCTAssertFalse(store.isActive)
        guard case .notStarted=outcome else {return XCTFail("stopped command dispatched")}
    }
}
