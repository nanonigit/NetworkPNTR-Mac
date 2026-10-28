import AppKit
import Observation
import SwiftUI
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class NativePickerAPI: BackendJSONTransport {
    struct Call { let method,path: String; let body: Data? }
    var calls: [Call] = []
    var version: Int64 = 2
    var bound = ["bound"]
    var unavailable = false
    var enabled = true
    var status = 200
    var holdWrite = false
    var holdPreview = false
    var heldWrite: CheckedContinuation<BackendHTTPResponse,any Error>?
    var heldPreview: CheckedContinuation<BackendHTTPResponse,any Error>?
    let literal = "\u{FEFF}e\u{301} 中文 한국어\u{FEFF}"
    func target(inherited: Bool = false) throws -> FindingRecord {
        var value: [String:Any] = ["id":"7","finding_id":"7","task_id":"11","name":"fixed","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"","evidence":"","ts":"raw"]
        if inherited { value["inherited"] = true; value["source_task_id"] = "11" }
        return try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:value))
    }
    var summary: [String:Any] { ["finding_id":"7","version":version,"report_version":1,"bindings":bound.enumerated().map { index,source -> [String:Any] in
        let id = String(21+index)
        return ["id":id,"finding_id":"7","snapshot_id":"snapshot-"+id,"role":"supporting","note":"","position":index,"created_at":"raw","snapshot":["id":"snapshot-"+id,"source_traffic_id":source,"captured_at":1792663200,"url":"https://fixture.invalid/","method":"GET","status":200,"content_type":"text/plain","req_len":0,"resp_len":0,"req_hash":String(repeating:"a",count:64),"resp_hash":String(repeating:"b",count:64)]]
    }] }
    func row(_ id: String) -> [String:Any] { ["id":id,"ts":"2026-10-22T10:00:00Z","host":"fixture.invalid","method":"GET","url":"https://fixture.invalid/"+id,"status":200,"content_type":"text/plain","resp_len":0] }
    func reply(_ value: Any) throws -> BackendHTTPResponse { .init(status:200,body:try JSONSerialization.data(withJSONObject:value)) }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append(.init(method:method,path:path,body:body))
        if method != "GET" {
            if holdWrite { return try await withCheckedThrowingContinuation { heldWrite = $0 } }
            if status != 200 { return .init(status:status,body:Data("private error".utf8)) }
            struct Ref: Decodable { let trafficId: String }
            struct Request: Decodable { let trafficRefs: [Ref] }
            let payload = try BackendJSONCoding.decode(Request.self,from:XCTUnwrap(body))
            bound += payload.trafficRefs.map(\.trafficId); version += 1; return try reply(summary)
        }
        if path.hasPrefix("/api/traffic/exchange?") {
            if holdPreview { return try await withCheckedThrowingContinuation { heldPreview = $0 } }
            return try reply(["req":literal,"resp":"blob:opaque-binary-marker"])
        }
        if path.hasPrefix("/api/traffic?") {
            if status != 200 { return .init(status:status,body:Data("private error".utf8)) }
            if unavailable { return try reply(["enabled":false,"exchanges":[]]) }
            let page = Int(URLComponents(string:path)?.queryItems?.first { $0.name == "page" }?.value ?? "0") ?? 0
            return try reply(["enabled":enabled,"count":4,"total":50,"page":page,"size":25,"exchanges":(page == 0 ? ["bound","é","e\u{301}"] : ["second"]).map(row)])
        }
        return try reply(summary)
    }
    var writes: [Call] { calls.filter { $0.method != "GET" } }
}

final class FindingCapturedPickerTests: XCTestCase {
    @MainActor private var workspaces: [FindingTrafficWorkspace] = []
    @MainActor private func workspace(_ api: NativePickerAPI, inherited: Bool = false,changes: @escaping @MainActor (UUID) async -> Void = {_ in}) async throws -> FindingTrafficWorkspace {
        let model = try FindingTrafficWorkspace(target:api.target(inherited:inherited),service:.init(client:api),capturedService:.init(client:api),onChanged:changes)
        await model.refresh(); workspaces.append(model); return model
    }
    @MainActor private func ready(_ api: NativePickerAPI,changes: @escaping @MainActor (UUID) async -> Void = {_ in}) async throws -> (FindingTrafficWorkspace,FindingCapturedPicker) {
        let model = try await workspace(api,changes:changes)
        XCTAssertTrue(model.openPicker(owner:model.id,version:api.version))
        let picker = try XCTUnwrap(model.picker); await picker.applyFilters(picker.filterTicket); return (model,picker)
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Controlled operation missing"); throw CancellationError()
    }
    @MainActor func testCrossPageSelectionUsesByteIDsAndExcludesAlreadyBound() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api), owner = picker.store.owner
        XCTAssertFalse(picker.toggle("bound",selected:true,owner:owner)); XCTAssertTrue(picker.selectPage(true,owner:owner))
        XCTAssertEqual(picker.store.selectedIDs.map { Data($0.utf8) },[Data("é".utf8),Data("e\u{301}".utf8)])
        await picker.page(forward:true,owner:owner); XCTAssertEqual(picker.store.query.page,1)
        XCTAssertFalse(picker.toggle("second",selected:true,owner:owner))
        XCTAssertTrue(picker.toggle("second",selected:true,owner:picker.store.owner)); XCTAssertEqual(picker.store.selectedCount,3)
        await picker.page(forward:false,owner:picker.store.owner); XCTAssertEqual(picker.store.selectedCount,3)
        XCTAssertTrue(picker.clearSelection(owner:picker.store.owner)); XCTAssertEqual(picker.store.selectedCount,0)
    }
    @MainActor func testDirtyDraftTicketRejectsOldResultActionsAndResetsPage() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api)
        await picker.page(forward:true,owner:picker.store.owner); let old = picker.filterTicket, owner = picker.store.owner
        picker.hostDraft = api.literal; picker.keywordDraft = "x + &"; picker.methodDraft = .post
        XCTAssertFalse(picker.canSelect); XCTAssertFalse(picker.toggle("second",selected:true,owner:owner))
        let count = api.calls.count; await picker.applyFilters(old); XCTAssertEqual(api.calls.count,count)
        await picker.applyFilters(picker.filterTicket)
        XCTAssertEqual(picker.store.query.page,0); XCTAssertEqual(Data(picker.store.query.host.utf8),Data(api.literal.utf8))
        XCTAssertTrue(api.calls.last?.path.contains("%EF%BB%BF") == true); XCTAssertTrue(api.calls.last?.path.contains("method=POST") == true)
    }
    @MainActor func testRecordedRawPreviewDoesNotFetchURLAndLatePreviewIsRevoked() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api)
        await picker.selectPreview("é",owner:picker.store.owner)
        XCTAssertEqual(Data(picker.store.preview.value?.request.utf8 ?? "".utf8),Data(api.literal.utf8))
        XCTAssertEqual(picker.store.preview.value?.response,"blob:opaque-binary-marker")
        api.holdPreview = true; let job = Task { await picker.selectPreview("e\u{301}",owner:picker.store.owner) }
        try await wait { api.heldPreview != nil }; picker.keywordDraft = "changed"; await picker.applyFilters(picker.filterTicket)
        api.heldPreview?.resume(returning:try api.reply(["req":"old","resp":"old"])); api.heldPreview = nil; await job.value
        XCTAssertNil(picker.store.preview.value); XCTAssertTrue(api.calls.allSatisfy { $0.path.hasPrefix("/api/") })
    }
    @MainActor func testConfirmedBindClosesPickerAndRefreshesMetadataExactlyOnce() async throws {
        let api = NativePickerAPI(); var changes = 0
        let (model,picker) = try await ready(api,changes:{ _ in changes += 1 })
        XCTAssertTrue(picker.selectPage(true,owner:picker.store.owner)); XCTAssertTrue(picker.canBind)
        let result = await picker.bind(owner:picker.store.owner); XCTAssertTrue(result)
        XCTAssertNil(model.picker); XCTAssertFalse(picker.isActive); XCTAssertEqual(changes,1); XCTAssertEqual(api.writes.count,1)
        XCTAssertEqual(api.bound.map { Data($0.utf8) },["bound","é","e\u{301}"].map { Data($0.utf8) })
    }
    @MainActor func testUnconfirmedBindCannotReplayAndOuterDepartureRetainsUnknown() async throws {
        let api = NativePickerAPI(), (model,picker) = try await ready(api)
        XCTAssertTrue(picker.selectPage(true,owner:picker.store.owner)); api.status = 503
        let result = await picker.bind(owner:picker.store.owner); XCTAssertFalse(result); XCTAssertEqual(model.store.unknownIDs,["7"])
        let replay = await picker.bind(owner:picker.store.owner); XCTAssertFalse(replay); XCTAssertEqual(api.writes.count,1)
        model.closePicker(id:picker.id); model.stop(); XCTAssertEqual(model.store.unknownIDs,["7"])
    }
    @MainActor func testForcedStopAfterDispatchKeepsWriteUntilTerminalAndDropsLateSuccess() async throws {
        let api = NativePickerAPI(), (model,picker) = try await ready(api)
        XCTAssertTrue(picker.selectPage(true,owner:picker.store.owner)); api.holdWrite = true
        let job = Task { await picker.bind(owner:picker.store.owner) }; try await wait { api.heldWrite != nil }
        model.closePicker(id:picker.id); XCTAssertEqual(model.picker?.id,picker.id)
        model.stop(); XCTAssertTrue(model.store.isMutating); XCTAssertEqual(model.store.unknownIDs,["7"])
        api.version += 1; api.heldWrite?.resume(returning:try api.reply(api.summary)); api.heldWrite = nil
        let result = await job.value; XCTAssertFalse(result); XCTAssertFalse(model.store.isMutating)
        XCTAssertNil(model.store.summary.value); XCTAssertNil(picker.store.catalog.value)
    }
    @MainActor func testOldPickerDismissBindingAndDisappearanceCannotCloseReplacement() async throws {
        let api = NativePickerAPI(), (model,first) = try await ready(api)
        let binding = FindingCapturedPickerBindings.presentation(model,id:first.id)
        model.closePicker(id:first.id); XCTAssertTrue(model.openPicker(owner:model.id,version:api.version))
        let second = try XCTUnwrap(model.picker); await second.applyFilters(second.filterTicket)
        first.stop(); binding.wrappedValue = nil; XCTAssertNil(binding.wrappedValue)
        XCTAssertEqual(model.picker?.id,second.id); XCTAssertTrue(second.store.isCurrent); XCTAssertNotNil(second.store.catalog.value)
    }
    @MainActor func testInheritedStaleVersionAndOtherDialogsCannotOpenPicker() async throws {
        let api = NativePickerAPI(), inherited = try await workspace(api,inherited:true), model = try await workspace(api)
        XCTAssertFalse(inherited.openPicker(owner:inherited.id,version:api.version))
        XCTAssertFalse(model.openPicker(owner:UUID(),version:api.version)); XCTAssertFalse(model.openPicker(owner:model.id,version:1))
        XCTAssertTrue(model.actions.openRemove("21",owner:model.id)); XCTAssertFalse(model.openPicker(owner:model.id,version:api.version))
    }
    @MainActor func testPickerCreationDepartureCannotRestorePresentationOrDispatch() async throws {
        let api = NativePickerAPI(), model = try await workspace(api)
        withObservationTracking { _ = model.picker } onChange: { MainActor.assumeIsolated { model.stop() } }
        _ = model.openPicker(owner:model.id,version:api.version)
        XCTAssertNil(model.picker); XCTAssertFalse(model.isActive); XCTAssertEqual(api.calls.count,1)
    }
    @MainActor func testUnchangedFilterTaskRestartPreservesPageAndCancelledDebounceDoesNotRead() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api)
        await picker.page(forward:true,owner:picker.store.owner)
        await picker.applyFilters(picker.filterTicket); XCTAssertEqual(picker.store.query.page,1)
        let count = api.calls.count, ticket = picker.filterTicket
        let task = Task { await picker.debounce(ticket) }; task.cancel(); await task.value
        XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testBusyPublicationDeparturePreventsBindDispatch() async throws {
        let api = NativePickerAPI(), (model,picker) = try await ready(api)
        XCTAssertTrue(picker.selectPage(true,owner:picker.store.owner))
        withObservationTracking { _ = picker.isSubmitting } onChange: { MainActor.assumeIsolated { model.stop() } }
        let result = await picker.bind(owner:picker.store.owner)
        XCTAssertFalse(result); XCTAssertTrue(api.writes.isEmpty); XCTAssertFalse(picker.isSubmitting)
        XCTAssertNil(model.picker); XCTAssertTrue(model.store.unknownIDs.isEmpty)
    }
    @MainActor func testStaleRowDraftAndPreviewCloseBindingsCannotReachReplacement() async throws {
        let api = NativePickerAPI(), (model,picker) = try await ready(api), owner = picker.store.owner
        let toggle = FindingCapturedPickerBindings.selected(picker,source:"é",owner:owner)
        let draft = FindingCapturedPickerBindings.draft(picker,key:\.hostDraft)
        toggle.wrappedValue = true; XCTAssertEqual(picker.store.selectedCount,1)
        await picker.selectPreview("é",owner:owner)
        await picker.selectPreview("e\u{301}",owner:owner)
        picker.closePreview("é",owner:owner); XCTAssertEqual(picker.store.selectedPreviewID.map {Data($0.utf8)},Data("e\u{301}".utf8))
        draft.wrappedValue = "host"; await picker.applyFilters(picker.filterTicket)
        XCTAssertFalse(toggle.wrappedValue); toggle.wrappedValue = false; XCTAssertEqual(picker.store.selectedCount,1)
        model.closePicker(id:picker.id); draft.wrappedValue = "late"; XCTAssertEqual(draft.wrappedValue,"")
        XCTAssertTrue(model.openPicker(owner:model.id,version:api.version)); XCTAssertEqual(model.picker?.hostDraft,"")
    }
    @MainActor func testPickerRendersBothLocalesThemesAndUnavailableErrorStatesWithoutDispatch() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api)
        for state in 0..<3 {
            if state == 1 { api.status = 503; await picker.reload(owner:picker.store.owner) }
            if state == 2 { api.status = 200; api.unavailable = true; await picker.reload(owner:picker.store.owner) }
            let count = api.calls.count
            for language in AppLanguage.allCases {
                for scheme in [ColorScheme.light,.dark] {
                    let host = NSHostingView(rootView:FindingCapturedPickerContent(picker:picker,close:{}).environment(\.locale,language.locale).environment(\.colorScheme,scheme))
                    host.frame = NSRect(x:0,y:0,width:980,height:720); host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
                    XCTAssertTrue(host.fittingSize.width.isFinite)
                }
            }
            XCTAssertEqual(api.calls.count,count)
        }
    }
    @MainActor func testDisabledHistoryUnavailableAndErrorStatesDoNotBecomeEmptySuccess() async throws {
        let api = NativePickerAPI(), (_,picker) = try await ready(api)
        api.enabled = false; await picker.reload(owner:picker.store.owner)
        XCTAssertFalse(picker.store.catalog.value?.isUnavailable ?? true); XCTAssertTrue(picker.canSelect)
        api.status = 503; await picker.reload(owner:picker.store.owner)
        XCTAssertNotNil(picker.store.catalog.failure); XCTAssertFalse(picker.canSelect)
        api.status = 200; api.unavailable = true; await picker.reload(owner:picker.store.owner)
        XCTAssertTrue(picker.store.catalog.value?.isUnavailable == true); XCTAssertFalse(picker.canSelect)
    }
}
