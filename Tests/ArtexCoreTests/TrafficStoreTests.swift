import Foundation
import Observation
import XCTest
@testable import ArtexCore

@MainActor private final class TrafficStateAPI: BackendJSONTransport {
    var calls:[(String,String,Data?)]=[]
    var holdRead=false,holdWrite=false,failRead=false,failWrite=false
    var captureAvailable=true
    var failPath:String?
    var pendingReads:[CheckedContinuation<BackendHTTPResponse,any Error>]=[]
    var pendingWrites:[CheckedContinuation<BackendHTTPResponse,any Error>]=[]
    var rowIDs=["é","e\u{301}"]
    var hostNames=["é","e\u{301}"]
    var onSend:(@MainActor (String)->Void)?
    func response(_ object:Any,status:Int=200) throws -> BackendHTTPResponse {.init(status:status,body:try JSONSerialization.data(withJSONObject:object))}
    func page(_ number:Int64=0) throws -> BackendHTTPResponse {
        try response(["enabled":false,"count":70,"total":70,"page":number,"size":50,"exchanges":rowIDs.map{["id":$0,"ts":"fixed","host":"fixture","method":"GET","url":"http://fixture.invalid/","content_type":"text/plain","status":200,"resp_len":0] as [String:Any]}])
    }
    func send(method:String,path:String,body:Data?,bearer:String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer);calls.append((method,path,body));onSend?(method)
        if method != "GET" {
            if holdWrite {return try await withCheckedThrowingContinuation{pendingWrites.append($0)}}
            if failWrite {return try response([:],status:500)}
            if method=="PUT" {return .init(status:200,body:body ?? Data())}
            return try response(["deleted":2,"reclaimed":4096])
        }
        if holdRead {return try await withCheckedThrowingContinuation{pendingReads.append($0)}}
        if failRead || failPath==path {return try response([:],status:503)}
        if path=="/api/settings" {return try response(["traffic_capture":false])}
        if path=="/api/traffic/hosts" {return try response(["hosts":hostNames.map{["host":$0,"count":1] as [String:Any]}])}
        if path.hasPrefix("/api/traffic/exchange?") {return try response(["req":"\u{FEFF}raw 中文 한국어","resp":"response"])}
        if !captureAvailable {return try response(["enabled":false,"exchanges":[]])}
        let number=Int64(URLComponents(string:path)?.queryItems?.first{$0.name=="page"}?.value ?? "0") ?? 0
        return try page(number)
    }
}
@MainActor final class TrafficStoreTests:XCTestCase {
    private func loaded(_ api:TrafficStateAPI) async -> TrafficStore {let store=TrafficStore(service:.init(client:api));await store.refresh();return store}
    private func wait(_ condition:()->Bool) async throws {for _ in 0..<200 {if condition(){return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Timed out")}
    func testReadSelectionAndQueryOwnershipPreserveByteDistinctCrossPageValues() async throws {
        let api=TrafficStateAPI(),store=await loaded(api),owner=store.owner
        XCTAssertTrue(store.toggleFlow(id:"é",selected:true,owner:owner));XCTAssertTrue(store.toggleFlow(id:"e\u{301}",selected:true,owner:owner))
        XCTAssertTrue(store.toggleHost("é",selected:true,owner:owner));XCTAssertTrue(store.toggleHost("e\u{301}",selected:true,owner:owner))
        XCTAssertEqual(store.selectedFlowIDs.map{Data($0.utf8)},api.rowIDs.map{Data($0.utf8)})
        XCTAssertTrue(store.selectExchange(id:"é",owner:owner));await store.refreshDetail();XCTAssertNotNil(store.detail.value)
        var query=store.query;query.page=1;XCTAssertTrue(store.configure(query,owner:owner));XCTAssertNotEqual(store.owner,owner)
        XCTAssertEqual(store.selectedFlowIDs.count,2);XCTAssertEqual(store.selectedHosts.count,2);XCTAssertEqual(Data(try XCTUnwrap(store.selectedExchange?.id).utf8),Data("é".utf8))
        XCTAssertFalse(store.canAutoRefresh);await store.refresh();XCTAssertEqual(store.catalog.value?.page,1)
        XCTAssertFalse(store.toggleFlow(id:"é",selected:false,owner:owner));XCTAssertTrue(store.hasPrevious)
    }
    func testLastGoodFailureAndInvalidQueryNeverBecomeFreshOrClearSelections() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);XCTAssertTrue(store.toggleFlow(id:"é",selected:true,owner:store.owner))
        api.failRead=true;await store.refresh();XCTAssertNotNil(store.catalog.value);XCTAssertTrue(store.catalog.isStale);XCTAssertNotNil(store.catalog.failure)
        XCTAssertFalse(store.toggleFlow(id:"e\u{301}",selected:true,owner:store.owner));var bad=store.query;bad.size=0;let count=api.calls.count
        XCTAssertFalse(store.configure(bad,owner:store.owner));XCTAssertEqual(api.calls.count,count);XCTAssertEqual(store.selectedFlowIDs.count,1)
    }
    func testConfirmationFreezesExactHostScopeAndCannotReplayOrMutateDrafts() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);XCTAssertTrue(store.toggleHost("é",selected:true,owner:store.owner))
        XCTAssertTrue(store.prepare(.selectedHosts,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation)
        XCTAssertFalse(store.toggleHost("e\u{301}",selected:true,owner:store.owner));var changed=store.query;changed.host="other";XCTAssertFalse(store.configure(changed,owner:store.owner))
        let before=api.calls.count;await store.refresh();XCTAssertEqual(api.calls.count,before)
        let result=await store.confirm(id:confirmation.id,owner:confirmation.owner);guard case .confirmed=result else {return XCTFail("Not confirmed")}
        let write=try XCTUnwrap(api.calls.last);XCTAssertEqual(write.1,"/api/traffic/hosts")
        struct Hosts:Decodable{let hosts:[String]};let payload=try BackendJSONCoding.decode(Hosts.self,from:XCTUnwrap(write.2));XCTAssertEqual(payload.hosts.map{Data($0.utf8)},[Data("é".utf8)])
        XCTAssertTrue(store.selectedHosts.isEmpty);guard case .notStarted=await store.confirm(id:confirmation.id,owner:confirmation.owner) else {return XCTFail("Replay")}
        XCTAssertEqual(api.calls.count,before+1)
    }
    func testSubstringConfirmationDoesNotDeleteByOtherFiltersAndCancelNeverDispatches() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);var query=store.query;query.host="api&x";query.body="narrow";XCTAssertTrue(store.configure(query,owner:store.owner));await store.refresh()
        XCTAssertTrue(store.prepare(.matchingHost,owner:store.owner));let first=try XCTUnwrap(store.confirmation);XCTAssertTrue(store.cancelConfirmation(id:first.id,owner:first.owner));let count=api.calls.count
        XCTAssertTrue(store.prepare(.matchingHost,owner:store.owner));let next=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:next.id,owner:next.owner)
        XCTAssertEqual(api.calls.count,count+1);let path=try XCTUnwrap(api.calls.last?.1);XCTAssertTrue(path.contains("host=api%26x"));XCTAssertFalse(path.contains("body="))
    }
    func testUnknownRequiresFreshCompleteReadAndExplicitExactRevisionAcknowledgment() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.failWrite=true
        XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation)
        guard case .unconfirmed=await store.confirm(id:confirmation.id,owner:confirmation.owner) else {return XCTFail("Expected unknown")}
        let revision=store.unknownRevision;XCTAssertTrue(store.hasUnknownOutcome);XCTAssertFalse(store.prepare(.purgeAll,owner:store.owner));XCTAssertFalse(store.acknowledgeUnknown(owner:store.owner,revision:revision))
        api.failRead=true;await store.refresh();XCTAssertFalse(store.canAcknowledgeUnknown)
        api.failRead=false;await store.refresh();XCTAssertTrue(store.hasUnknownOutcome);XCTAssertTrue(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledgeUnknown(owner:UUID(),revision:revision));XCTAssertFalse(store.acknowledgeUnknown(owner:store.owner,revision:UUID()))
        XCTAssertTrue(store.acknowledgeUnknown(owner:store.owner,revision:revision));XCTAssertFalse(store.hasUnknownOutcome);XCTAssertNotEqual(store.unknownRevision,revision)
    }
    func testStopResumeKeepsUnknownAndSessionResetScrubsScopeUntilHeldWriteSettles() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.holdWrite=true
        XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation)
        let job=Task{await store.confirm(id:confirmation.id,owner:confirmation.owner)};try await wait{api.pendingWrites.count==1}
        store.stop();XCTAssertTrue(store.hasUnknownOutcome);XCTAssertTrue(store.isMutating);XCTAssertNil(store.catalog.value)
        store.resume();XCTAssertFalse(store.prepare(.purgeAll,owner:store.owner));store.resetSession();XCTAssertNil(store.unknownChange);XCTAssertTrue(store.hasUnknownOutcome);XCTAssertTrue(store.isMutating)
        api.pendingWrites.removeFirst().resume(returning:try api.response(["deleted":70,"reclaimed":0]));guard case .discarded=await job.value else {return XCTFail("Late write")}
        XCTAssertFalse(store.isMutating);XCTAssertNil(store.lastReceipt);XCTAssertTrue(store.hasUnknownOutcome)
        store.resume();await store.refresh();XCTAssertTrue(store.acknowledgeUnknown(owner:store.owner,revision:store.unknownRevision))
    }
    func testOldReadCannotResurrectAfterConfigureOrStop() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.holdRead=true
        let old=Task{await store.refresh()};try await wait{api.pendingReads.count==1}
        var query=store.query;query.page=1;XCTAssertTrue(store.configure(query,owner:store.owner));api.holdRead=false;await store.refresh();XCTAssertEqual(store.catalog.value?.page,1)
        api.pendingReads.removeFirst().resume(returning:try api.page());await old.value;XCTAssertEqual(store.catalog.value?.page,1)
        api.holdRead=true;let stopped=Task{await store.refresh()};try await wait{api.pendingReads.count==1};store.stop()
        api.pendingReads.removeFirst().resume(returning:try api.page(1));await stopped.value;XCTAssertNil(store.catalog.value);XCTAssertFalse(store.isActive)
    }
    func testPrecancelledConfirmationAndStopAtDispatchDoNotSendOrMarkUnknown() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let first=try XCTUnwrap(store.confirmation);let count=api.calls.count
        let cancelled=Task{await store.confirm(id:first.id,owner:first.owner)};cancelled.cancel();guard case .notStarted=await cancelled.value else {return XCTFail("Precancel")};XCTAssertEqual(api.calls.count,count)
        _ = await store.confirm(id:first.id,owner:first.owner,onDispatch:{store.stop()})
        XCTAssertFalse(store.hasUnknownOutcome);XCTAssertFalse(store.isMutating);XCTAssertEqual(api.calls.count,count)
    }
    func testCaptureReceiptAndConfirmedDeletionResetOnlyTheirDocumentedState() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);XCTAssertTrue(store.toggleFlow(id:"é",selected:true,owner:store.owner));XCTAssertTrue(store.toggleHost("é",selected:true,owner:store.owner))
        XCTAssertTrue(store.prepare(.capture(true),owner:store.owner));let capture=try XCTUnwrap(store.confirmation);guard case .confirmed=await store.confirm(id:capture.id,owner:capture.owner) else {return XCTFail("Capture")}
        XCTAssertEqual(store.settings.value?.trafficCapture,true);XCTAssertTrue(store.catalog.isStale);await store.refresh()
        var query=store.query;query.page=1;query.host="é";XCTAssertTrue(store.configure(query,owner:store.owner));await store.refresh();XCTAssertTrue(store.prepare(.matchingHost,owner:store.owner));let deletion=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:deletion.id,owner:deletion.owner)
        XCTAssertEqual(store.query.page,0);XCTAssertEqual(store.selectedFlowIDs.count,1);XCTAssertEqual(store.selectedHosts.count,1);XCTAssertNil(store.selectedExchange)
    }
    func testBatchSelectionKeepsByteIdentitiesAndCrossPageSelectionsWithRevisions() async throws {
        let api=TrafficStateAPI(),store=await loaded(api)
        XCTAssertTrue(store.selectVisibleFlows(true,owner:store.owner));XCTAssertTrue(store.selectAllHosts(true,owner:store.owner));XCTAssertEqual(store.selectedFlowIDs.count,2);XCTAssertEqual(store.selectedHosts.count,2)
        let revision=store.flowRevision;XCTAssertTrue(store.toggleFlow(id:"é",selected:true,owner:store.owner));XCTAssertEqual(store.flowRevision,revision)
        var query=store.query;query.page=1;api.rowIDs=["third"];XCTAssertTrue(store.configure(query,owner:store.owner));await store.refresh()
        XCTAssertTrue(store.selectVisibleFlows(true,owner:store.owner));XCTAssertEqual(store.selectedFlowIDs.count,3);XCTAssertNotEqual(store.flowRevision,revision)
        XCTAssertTrue(store.selectVisibleFlows(false,owner:store.owner));XCTAssertEqual(store.selectedFlowIDs.count,2)
        XCTAssertTrue(store.clearFlowSelection(owner:store.owner));XCTAssertTrue(store.selectAllHosts(false,owner:store.owner));XCTAssertTrue(store.selectedFlowIDs.isEmpty);XCTAssertTrue(store.selectedHosts.isEmpty)
    }
    func testOldScopedTeardownCannotStopNewOwnerAndPublicationStopCannotResurrectSelection() async throws {
        let api=TrafficStateAPI(),store=await loaded(api),old=store.owner;var query=store.query;query.host="changed"
        XCTAssertTrue(store.configure(query,owner:old));await store.refresh();XCTAssertFalse(store.stop(ifOwnedBy:old));XCTAssertTrue(store.isActive)
        withObservationTracking{_ = store.selectedFlowIDs}onChange:{MainActor.assumeIsolated{store.stop();store.resume()}}
        XCTAssertFalse(store.toggleFlow(id:"é",selected:true,owner:store.owner));XCTAssertFalse(store.isActive);XCTAssertTrue(store.selectedFlowIDs.isEmpty)
    }
    func testResetDuringBusyAndStopDuringReceiptStayScopedAndDoNotReplay() async throws {
        for reset in [true,false] {
            let api=TrafficStateAPI(),store=await loaded(api);XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation);let calls=api.calls.count
            if reset {withObservationTracking{_ = store.isMutating}onChange:{MainActor.assumeIsolated{store.resetSession();store.resume()}}}
            else {api.onSend={method in if method != "GET" {withObservationTracking{_ = store.lastReceipt}onChange:{MainActor.assumeIsolated{store.stop();store.resume()}}}}}
            let result=await store.confirm(id:confirmation.id,owner:confirmation.owner)
            if reset {guard case .notStarted=result else {return XCTFail("Reset before dispatch")};XCTAssertEqual(api.calls.count,calls);XCTAssertFalse(store.hasUnknownOutcome)}
            else {guard case .discarded=result else {return XCTFail("Departed receipt")};XCTAssertEqual(api.calls.count,calls+1);XCTAssertTrue(store.hasUnknownOutcome)}
            XCTAssertFalse(store.isActive);XCTAssertFalse(store.isMutating);XCTAssertNil(store.lastReceipt);XCTAssertNil(store.catalog.value)
        }
    }
    func testResetScrubsAppliedQueryAndRetainsOnlyGenericUncertainty() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);var query=store.query;query.host="private-host";query.keyword="private-query";query.body="private-body";query.path="/private-path"
        XCTAssertTrue(store.configure(query,owner:store.owner));await store.refresh();api.failWrite=true
        XCTAssertTrue(store.prepare(.matchingHost,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:confirmation.id,owner:confirmation.owner)
        XCTAssertNotNil(store.unknownChange);store.resetSession()
        XCTAssertTrue(store.hasUnknownOutcome);XCTAssertNil(store.unknownChange);XCTAssertNil(store.catalog.value);XCTAssertTrue(store.selectedHosts.isEmpty)
        XCTAssertEqual(store.query.host,"");XCTAssertEqual(store.query.keyword,"");XCTAssertEqual(store.query.body,"");XCTAssertEqual(store.query.path,"")
    }
    func testUnavailableIndexCannotSatisfyFreshUnknownRecovery() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.failWrite=true
        XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:confirmation.id,owner:confirmation.owner)
        api.captureAvailable=false;await store.refresh();XCTAssertEqual(store.catalog.value?.isUnavailable,true)
        XCTAssertFalse(store.canAcknowledgeUnknown);XCTAssertFalse(store.acknowledgeUnknown(owner:store.owner,revision:store.unknownRevision));XCTAssertTrue(store.hasUnknownOutcome)
        api.captureAvailable=true;await store.refresh();XCTAssertTrue(store.acknowledgeUnknown(owner:store.owner,revision:store.unknownRevision))
    }
    func testPartialRecoveryFailuresAndChangedOwnerNeverUnlockOldAcknowledgment() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.failWrite=true
        XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:confirmation.id,owner:confirmation.owner)
        for path in ["/api/traffic/hosts","/api/settings"] {api.failPath=path;await store.refresh();XCTAssertFalse(store.canAcknowledgeUnknown);XCTAssertTrue(store.hasUnknownOutcome)}
        api.failPath=nil;await store.refresh();XCTAssertTrue(store.canAcknowledgeUnknown);let old=store.owner,revision=store.unknownRevision
        var query=store.query;query.host="é";XCTAssertTrue(store.configure(query,owner:old));XCTAssertFalse(store.canAcknowledgeUnknown);XCTAssertFalse(store.acknowledgeUnknown(owner:old,revision:revision))
        await store.refresh();XCTAssertTrue(store.acknowledgeUnknown(owner:store.owner,revision:revision))
    }
    func testResetRequestedDuringTeardownWinsAndDoesNotLeaveDeferredStop() async throws {
        let api=TrafficStateAPI(),store=await loaded(api);api.failWrite=true
        var query=store.query;query.host="scope";XCTAssertTrue(store.configure(query,owner:store.owner));await store.refresh()
        XCTAssertTrue(store.prepare(.matchingHost,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation);_ = await store.confirm(id:confirmation.id,owner:confirmation.owner)
        withObservationTracking{_ = store.isActive}onChange:{MainActor.assumeIsolated{store.resetSession()}}
        store.stop();XCTAssertTrue(store.hasUnknownOutcome);XCTAssertNil(store.unknownChange);XCTAssertEqual(store.query.host,"");XCTAssertFalse(store.isActive)
        store.resume();XCTAssertTrue(store.isActive);await store.refresh();XCTAssertTrue(store.canAcknowledgeUnknown)
    }
    func testEmptyAndStaleControlsRejectInvalidScopesWithoutRequestsOrRevisionChurn() async throws {
        let api=TrafficStateAPI(),unloaded=TrafficStore(service:.init(client:api))
        XCTAssertFalse(unloaded.prepare(.purgeAll,owner:unloaded.owner));XCTAssertFalse(unloaded.prepare(.capture(true),owner:unloaded.owner));XCTAssertFalse(unloaded.selectVisibleFlows(true,owner:unloaded.owner))
        let store=await loaded(api),owner=store.owner,calls=api.calls.count
        XCTAssertTrue(store.configure(store.query,owner:owner));XCTAssertEqual(store.owner,owner);XCTAssertTrue(store.hasNext);XCTAssertFalse(store.hasPrevious);XCTAssertTrue(store.canAutoRefresh)
        XCTAssertFalse(store.prepare(.matchingHost,owner:owner));XCTAssertFalse(store.prepare(.selectedHosts,owner:owner));XCTAssertFalse(store.toggleFlow(id:"missing",selected:true,owner:owner));XCTAssertFalse(store.toggleHost("missing",selected:true,owner:owner));XCTAssertFalse(store.selectExchange(id:"missing",owner:owner));XCTAssertTrue(store.selectExchange(id:nil,owner:owner))
        XCTAssertTrue(store.toggleHost("é",selected:true,owner:owner));XCTAssertTrue(store.toggleHost("é",selected:false,owner:owner));XCTAssertTrue(store.toggleHost("é",selected:true,owner:owner));XCTAssertTrue(store.clearHostSelection(owner:owner));let revision=store.hostRevision;XCTAssertTrue(store.clearHostSelection(owner:owner));XCTAssertEqual(store.hostRevision,revision)
        XCTAssertTrue(store.prepare(.purgeAll,owner:owner));let confirmation=try XCTUnwrap(store.confirmation);XCTAssertFalse(store.cancelConfirmation(id:UUID(),owner:owner));XCTAssertTrue(store.cancelConfirmation(id:confirmation.id,owner:owner));XCTAssertEqual(api.calls.count,calls)
    }
    func testSynchronousStopDuringBusyAndReadPublicationRevokesDispatch() async throws {
        for write in [false,true] {
            let api=TrafficStateAPI(),store=await loaded(api);let count=api.calls.count
            if write {
                XCTAssertTrue(store.prepare(.purgeAll,owner:store.owner));let confirmation=try XCTUnwrap(store.confirmation)
                withObservationTracking{_ = store.isMutating}onChange:{MainActor.assumeIsolated{store.stop()}}
                guard case .notStarted=await store.confirm(id:confirmation.id,owner:confirmation.owner) else {return XCTFail("Busy stop")}
            } else {
                withObservationTracking{_ = store.catalog.isLoading}onChange:{MainActor.assumeIsolated{store.stop()}}
                await store.refresh()
            }
            XCTAssertFalse(store.isActive);XCTAssertNil(store.catalog.value);XCTAssertFalse(store.hasUnknownOutcome);XCTAssertEqual(api.calls.count,count)
        }
    }
}
