import AppKit
import Observation
import SwiftUI
import XCTest
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor private final class EvidenceActionAPI: BackendJSONTransport {
    struct Call { let method,path: String; let body: Data? }
    var calls: [Call] = []
    var version: Int64 = 2
    var ids = ["21","22"]
    var status = 200
    var role = "future-role"
    var note = "\u{FEFF}e\u{301} 中文 한국어\u{FEFF}"
    var holdWrite = false
    var held: CheckedContinuation<BackendHTTPResponse,any Error>?
    var row: [String:Any] { ["id":"7","finding_id":"7","task_id":"11","name":"raw","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"","evidence":"","report":"","ts":"raw"] }
    func target(inherited: Bool = false) throws -> FindingRecord {
        var value = row; value["inherited"] = inherited
        if inherited { value["source_task_id"] = "11" }
        return try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:value))
    }
    func binding(_ id: String,position: Int) -> [String:Any] {
        ["id":id,"finding_id":"7","snapshot_id":"snap-"+id,"role":role,"note":note,"position":position,"created_at":"raw",
         "snapshot":["id":"snap-"+id,"source_traffic_id":"source-"+id,"captured_at":1792663200,"url":"https://fixture.invalid/","method":"GET","status":200,"content_type":"text/plain","req_hash":String(repeating:"a",count:64),"resp_hash":String(repeating:"b",count:64),"req_len":0,"resp_len":0]]
    }
    var summary: [String:Any] { ["finding_id":"7","version":version,"report_version":1,"bindings":ids.enumerated().map { binding($0.element,position:$0.offset) }] }
    func reply(_ object: Any,status: Int = 200) throws -> BackendHTTPResponse { .init(status:status,body:try JSONSerialization.data(withJSONObject:object)) }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append(.init(method:method,path:path,body:body))
        if method != "GET" {
            if holdWrite { return try await withCheckedThrowingContinuation { held = $0 } }
            guard status == 200 else { return .init(status:status,body:Data("private server content".utf8)) }
            version += 1
            if method == "DELETE" { ids.removeAll { path.hasSuffix("/"+$0) } }
            return try reply(summary)
        }
        if path.contains("/traffic") { return try reply(summary) }
        if path == "/api/exploration/findings/7" { return try reply(row) }
        return try reply(["items":[row],"total":1,"page":1,"page_size":20])
    }
    var writes: [Call] { calls.filter { $0.method != "GET" } }
}

final class FindingTrafficActionTests: XCTestCase {
    @MainActor private func loaded(_ api: EvidenceActionAPI, inherited: Bool = false,onChanged: @escaping @MainActor (UUID) async -> Void = {_ in}) async throws -> FindingTrafficWorkspace {
        let model = try FindingTrafficWorkspace(target:api.target(inherited:inherited),service:.init(client:api),onChanged:onChanged)
        await model.refresh(); return model
    }
    @MainActor private func parent(_ api: EvidenceActionAPI) async throws -> FindingScreenModel {
        let model = FindingScreenModel(store:FindingStore(service:.init(client:api)),trafficService:.init(client:api))
        await model.store.refreshView(); await model.selectDetail(id:"7",owner:model.store.viewOwner)
        XCTAssertTrue(model.beginTraffic(owner:model.store.viewOwner,revision:model.detailRevision))
        await model.trafficWorkspace?.refresh(); return model
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Controlled handoff missing"); throw CancellationError()
    }
    @MainActor private func submit(_ model: FindingTrafficWorkspace) async throws -> Bool { await model.actions.submit(id:try XCTUnwrap(model.actions.dialog).id) }
    private func body(_ call: EvidenceActionAPI.Call) throws -> [String:Any] { try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(call.body)) as? [String:Any]) }
    @MainActor func testUnknownRoleRequiresExplicitChoiceAndNoteBytesArePreserved() async throws {
        let api = EvidenceActionAPI(); var changes = 0
        let model = try await loaded(api,onChanged:{ _ in changes += 1 })
        XCTAssertTrue(model.actions.openEdit("21",owner:model.id)); XCTAssertNil(model.actions.roleDraft)
        XCTAssertEqual(Data(model.actions.noteDraft.utf8),Data(api.note.utf8))
        let denied = try await submit(model); XCTAssertFalse(denied); XCTAssertTrue(api.writes.isEmpty)
        model.actions.roleDraft = .proof
        let saved = try await submit(model); XCTAssertTrue(saved); XCTAssertNil(model.actions.dialog); XCTAssertEqual(changes,1)
        let sent = try body(XCTUnwrap(api.writes.last)); XCTAssertEqual(sent["version"] as? Int,2)
        XCTAssertEqual(sent["role"] as? String,"proof"); struct Edit: Decodable { let note: String }
        let payload = try BackendJSONCoding.decode(Edit.self,from:XCTUnwrap(api.writes.last?.body))
        XCTAssertEqual(Data(payload.note.utf8),Data(api.note.utf8))
        XCTAssertEqual(api.writes.first?.path,"/api/exploration/findings/7/traffic/21")
    }
    @MainActor func testAdjacentOrderUsesExactMembershipAndRejectsBoundaries() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        XCTAssertFalse(model.actions.openMove("21",delta:-1,owner:model.id)); XCTAssertFalse(model.actions.openMove("22",delta:1,owner:model.id))
        XCTAssertFalse(model.actions.openMove("21",delta:2,owner:model.id))
        XCTAssertTrue(model.actions.openMove("22",delta:-1,owner:model.id))
        let saved = try await submit(model); XCTAssertTrue(saved)
        let sent = try body(XCTUnwrap(api.writes.last)); XCTAssertEqual(sent["binding_ids"] as? [String],["22","21"]); XCTAssertEqual(sent["version"] as? Int,2)
    }
    @MainActor func testStaleVersionDialogAndOldDialogBindingsCannotSubmitOrAffectReplacement() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        XCTAssertTrue(model.actions.openRemove("21",owner:model.id))
        let first = try XCTUnwrap(model.actions.dialog), binding = FindingTrafficActionBindings.dialog(model.actions,id:model.actions.dialog?.id)
        api.version += 1; await model.store.refreshSummary()
        let rejected = try await submit(model); XCTAssertFalse(rejected); XCTAssertTrue(api.writes.isEmpty)
        model.actions.close(id:first.id); XCTAssertTrue(model.actions.openEdit("22",owner:model.id))
        let second = try XCTUnwrap(model.actions.dialog)
        XCTAssertNil(binding.wrappedValue); binding.wrappedValue = nil
        XCTAssertEqual(model.actions.dialog?.id,second.id)
        let stale = await model.actions.submit(id:first.id); XCTAssertFalse(stale); XCTAssertTrue(api.writes.isEmpty)
    }
    @MainActor func testInheritedWrongOwnerAndExportDialogGatesRejectCommands() async throws {
        let api = EvidenceActionAPI(), inherited = try await loaded(api,inherited:true), model = try await loaded(api)
        XCTAssertFalse(inherited.actions.openEdit("21",owner:inherited.id)); XCTAssertFalse(inherited.actions.openRemove("21",owner:inherited.id))
        XCTAssertFalse(model.actions.openRemove("21",owner:UUID()))
        XCTAssertTrue(model.actions.openEdit("21",owner:model.id)); XCTAssertFalse(model.actions.openRemove("22",owner:model.id))
        let calls = api.calls.count; await model.refresh(); await model.selectBinding("21",owner:model.id)
        XCTAssertEqual(api.calls.count,calls); XCTAssertTrue(api.writes.isEmpty)
    }
    @MainActor func testConflictCannotReplayAndRefreshDoesNotAcknowledgeUnknown() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api); api.status = 409
        XCTAssertTrue(model.actions.openRemove("21",owner:model.id)); let context = try XCTUnwrap(model.actions.dialog)
        let failed = try await submit(model); XCTAssertFalse(failed); XCTAssertEqual(model.store.unknownIDs,["7"])
        let replay = try await submit(model); XCTAssertFalse(replay); XCTAssertEqual(api.writes.count,1)
        model.actions.close(id:context.id); api.status = 200; await model.refresh()
        XCTAssertEqual(model.store.unknownIDs,["7"]); XCTAssertFalse(model.actions.openEdit("21",owner:model.id))
        XCTAssertTrue(model.actions.openAcknowledgement(owner:model.id)); let acknowledged = try await submit(model)
        XCTAssertTrue(acknowledged); XCTAssertTrue(model.store.unknownIDs.isEmpty); XCTAssertEqual(api.writes.count,1)
    }
    @MainActor func testCloseRetainsUnsettledWriteAndUnknownRecoveryAcrossSheets() async throws {
        let api = EvidenceActionAPI(), screen = try await parent(api), first = try XCTUnwrap(screen.trafficWorkspace)
        XCTAssertTrue(first.actions.openRemove("21",owner:first.id)); api.holdWrite = true
        let job = Task { try await self.submit(first) }; try await wait { api.held != nil }
        screen.closeTraffic(id:first.id); XCTAssertNil(screen.trafficWorkspace)
        XCTAssertTrue(screen.busy); XCTAssertFalse(screen.beginDelete(try api.target()))
        api.version += 1; api.ids = ["22"]; api.held?.resume(returning:try api.reply(api.summary)); api.held = nil
        let result = try await job.value; XCTAssertFalse(result); XCTAssertFalse(screen.busy)
        XCTAssertEqual(screen.trafficUnknownIDs,["7"]); XCTAssertFalse(screen.beginDelete(try api.target()))
        XCTAssertTrue(screen.configureFilters(.init(search:"different")))
        XCTAssertTrue(screen.beginTrafficRecovery(id:"7")); let recovered = try XCTUnwrap(screen.trafficWorkspace)
        XCTAssertTrue(recovered.store === first.store); await recovered.refresh()
        XCTAssertTrue(recovered.actions.openAcknowledgement(owner:recovered.id)); let ack = try await submit(recovered); XCTAssertTrue(ack)
        screen.closeTraffic(id:recovered.id); XCTAssertTrue(screen.trafficUnknownIDs.isEmpty)
        XCTAssertEqual(api.writes.count,1)
    }
    @MainActor func testConfirmedMutationRefreshesParentFindingMetadata() async throws {
        let api = EvidenceActionAPI(), screen = try await parent(api), model = try XCTUnwrap(screen.trafficWorkspace)
        let before = api.calls.filter { $0.path == "/api/exploration/findings/7" }.count
        XCTAssertTrue(model.actions.openRemove("21",owner:model.id)); let saved = try await submit(model); XCTAssertTrue(saved)
        XCTAssertGreaterThan(api.calls.filter { $0.path == "/api/exploration/findings/7" }.count,before)
        XCTAssertEqual(model.store.summary.value?.bindings.map(\.id),["22"])
    }
    @MainActor func testStaleRenderedVersionCannotOpenNewConfirmation() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        api.version = 3; await model.refresh()
        XCTAssertFalse(model.actions.openEdit("21",owner:model.id,version:2))
        XCTAssertFalse(model.actions.openRemove("21",owner:model.id,version:2))
        XCTAssertFalse(model.actions.openMove("21",delta:1,owner:model.id,version:2))
        XCTAssertNil(model.actions.dialog); XCTAssertTrue(api.writes.isEmpty)
    }
    @MainActor func testStopDuringSubmittingPublicationPreventsDispatch() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        XCTAssertTrue(model.actions.openRemove("21",owner:model.id))
        withObservationTracking { _ = model.actions.isSubmitting } onChange: { MainActor.assumeIsolated { model.stop() } }
        let result = try await submit(model); XCTAssertFalse(result); XCTAssertTrue(api.writes.isEmpty)
        XCTAssertTrue(model.store.unknownIDs.isEmpty); XCTAssertNil(model.actions.dialog); XCTAssertFalse(model.actions.isSubmitting)
    }
    @MainActor func testCancelledDispatchedEditCannotReplayAndCapturedDraftBindingsAreRevoked() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        XCTAssertTrue(model.actions.openEdit("21",owner:model.id)); let id = try XCTUnwrap(model.actions.dialog).id
        let note = FindingTrafficActionBindings.note(model.actions,id:id), role = FindingTrafficActionBindings.role(model.actions,id:id)
        role.wrappedValue = "proof"; note.wrappedValue = "literal edit"
        api.holdWrite = true; let job = Task { await model.actions.submit(id:id) }; try await wait { api.held != nil }
        note.wrappedValue = "must not replace"; role.wrappedValue = "baseline"
        XCTAssertEqual(model.actions.noteDraft,"literal edit"); XCTAssertEqual(model.actions.roleDraft,.proof)
        job.cancel(); api.version += 1; api.held?.resume(returning:try api.reply(api.summary)); api.held = nil
        let result = await job.value; XCTAssertFalse(result); XCTAssertEqual(model.store.unknownIDs,["7"])
        model.actions.close(id:id); XCTAssertEqual(note.wrappedValue,""); XCTAssertEqual(role.wrappedValue,"")
        XCTAssertEqual(api.writes.count,1)
    }
    @MainActor func testDelayedOldSheetStopCannotRevokeReplacementStore() async throws {
        let api = EvidenceActionAPI(), screen = try await parent(api), old = try XCTUnwrap(screen.trafficWorkspace)
        screen.closeTraffic(id:old.id)
        XCTAssertTrue(screen.beginTraffic(owner:screen.store.viewOwner,revision:screen.detailRevision))
        let current = try XCTUnwrap(screen.trafficWorkspace); await current.refresh()
        let owner = current.store.owner; old.stop()
        XCTAssertTrue(current.store.isActive); XCTAssertEqual(current.store.owner,owner)
        XCTAssertNotNil(current.store.summary.value); XCTAssertTrue(current.actions.openRemove("21",owner:current.id))
    }
    @MainActor func testOldMutationCleanupAfterResetCannotStopNewSessionWrite() async throws {
        let api = EvidenceActionAPI(), screen = try await parent(api), old = try XCTUnwrap(screen.trafficWorkspace)
        api.holdWrite = true; XCTAssertTrue(old.actions.openRemove("21",owner:old.id))
        let first = Task { try await self.submit(old) }; try await wait { api.held != nil }
        let oldReply = try XCTUnwrap(api.held); api.held = nil; screen.reset()
        await screen.store.refreshView(); await screen.selectDetail(id:"7",owner:screen.store.viewOwner)
        XCTAssertTrue(screen.beginTraffic(owner:screen.store.viewOwner,revision:screen.detailRevision))
        let current = try XCTUnwrap(screen.trafficWorkspace); await current.refresh()
        XCTAssertTrue(current.actions.openRemove("22",owner:current.id))
        let second = Task { try await self.submit(current) }; try await wait { api.held != nil }
        let owner = current.store.owner; api.version += 1; oldReply.resume(returning:try api.reply(api.summary))
        let firstResult = try await first.value; XCTAssertFalse(firstResult)
        XCTAssertTrue(current.store.isActive); XCTAssertEqual(current.store.owner,owner); XCTAssertTrue(current.store.isMutating)
        XCTAssertTrue(current.store.unknownIDs.isEmpty)
        api.version += 1; api.ids = ["21"]; api.held?.resume(returning:try api.reply(api.summary)); api.held = nil
        let secondResult = try await second.value; XCTAssertTrue(secondResult); XCTAssertTrue(screen.trafficUnknownIDs.isEmpty)
    }
    @MainActor func testActionDialogsRenderBothLocalesWithoutSendingCommands() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        for kind in 0..<3 {
            let opened = switch kind {
            case 0: model.actions.openEdit("21",owner:model.id)
            case 1: model.actions.openRemove("21",owner:model.id)
            default: model.actions.openMove("22",delta:-1,owner:model.id)
            }
            XCTAssertTrue(opened); let id = try XCTUnwrap(model.actions.dialog).id
            for language in AppLanguage.allCases {
                let host = NSHostingView(rootView:FindingTrafficActionView(actions:model.actions,id:id).environment(\.locale,language.locale))
                host.frame = NSRect(x:0,y:0,width:540,height:420); host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
                XCTAssertTrue(host.fittingSize.width.isFinite)
            }
            model.actions.close(id:id)
        }
        XCTAssertTrue(api.writes.isEmpty)
    }
    @MainActor func testStopDuringDialogPublicationClearsDraftWithoutDispatch() async throws {
        let api = EvidenceActionAPI(), model = try await loaded(api)
        withObservationTracking { _ = model.actions.dialog } onChange: { MainActor.assumeIsolated { model.stop() } }
        _ = model.actions.openEdit("21",owner:model.id)
        XCTAssertFalse(model.isActive); XCTAssertNil(model.actions.dialog); XCTAssertEqual(model.actions.noteDraft,""); XCTAssertTrue(api.writes.isEmpty)
    }
}
