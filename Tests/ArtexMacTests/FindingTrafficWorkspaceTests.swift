import Observation
import AppKit
import SwiftUI
import CryptoKit
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class EvidenceWorkspaceAPI: BackendJSONTransport {
    var calls: [String] = []
    var hold = false
    var pending: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    var status = 200
    let literal = "\u{FEFF}e\u{301} 中文 한국어"
    var binding: [String: Any] {
        ["id":"21", "finding_id":"7", "snapshot_id":"snap", "role":"future-role", "note":literal,
         "position":0, "created_at":"raw", "snapshot":["id":"snap", "source_traffic_id":"opaque",
         "captured_at":1792663200000, "url":"https://fixture.invalid/", "method":"POST", "status":200,
         "content_type":"application/octet-stream", "req_head":literal, "resp_head":"HTTP/1.1 200 OK",
         "req_hash":Self.hash(Data()), "resp_hash":Self.hash(Data([0,255,97])), "req_len":0, "resp_len":3]]
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    func page(_ content: String, offset: Int = 0, next: Int = 1, total: Int = 3, binary: Bool = false) -> [String: Any] {
        ["content":content, "offset":offset, "next_offset":next, "total":total, "truncated":next < total, "binary":binary]
    }
    func response(_ value: Any) throws -> BackendHTTPResponse { .init(status:status,body:try JSONSerialization.data(withJSONObject:value)) }
    var row: [String: Any] { ["id":"7", "finding_id":"7", "task_id":"11", "name":literal, "vulnclass":"CWE-79", "severity":"high", "status":"pending", "summary":"", "evidence":"", "report":"", "ts":"raw"] }
    func target(inherited: Bool = false, legacy: Bool = false) throws -> FindingRecord {
        var value = row
        if inherited { value["inherited"] = true; value["source_task_id"] = "11" }
        if legacy { value.removeValue(forKey:"finding_id") }
        return try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:value))
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(method,"GET"); XCTAssertNil(body); XCTAssertNil(bearer); calls.append(path)
        if hold { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if path.contains("/body?") {
            let offset = Int(URLComponents(string:path)?.queryItems?.first { $0.name == "offset" }?.value ?? "0") ?? 0
            return try response(page(literal,offset:offset,next:3))
        }
        if path.contains("/traffic/21") { return try response(["binding":binding,"request":page("",next:0,total:0),"response":page(literal)]) }
        if path.contains("/traffic") { return try response(["finding_id":"7","version":2,"report_version":1,"bindings":[binding]]) }
        if path == "/api/exploration/findings/7" { return try response(row) }
        return try response(["items":[row],"total":1,"page":1,"page_size":20])
    }
}

@MainActor private final class EvidenceDestinationFixture: EvidenceDestinationChoosing {
    var url: URL?
    var names: [String] = []
    var pending: CheckedContinuation<URL?, Never>?
    var hold = false
    var cancels = 0
    func choose(suggestedFilename: String) async -> URL? {
        names.append(suggestedFilename)
        if hold { return await withCheckedContinuation { pending = $0 } }
        return url
    }
    func cancel() { cancels += 1; pending?.resume(returning:nil); pending = nil }
}

@MainActor private final class ReentrantEvidenceDeparture {
    weak var model: FindingTrafficWorkspace?
    var changes = 0
    func arm() {
        guard let model else { return }
        withObservationTracking { _ = model.isActive } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changes += 1
                if self.changes < 4 { self.arm(); self.model?.stop() }
            }
        }
    }
}

final class FindingTrafficWorkspaceTests: XCTestCase {
    @MainActor private func make(_ api: EvidenceWorkspaceAPI, inherited: Bool = false, exporter: FindingEvidenceExporter? = nil) throws -> FindingTrafficWorkspace {
        try FindingTrafficWorkspace(target:api.target(inherited:inherited),service:.init(client:api),exporter:exporter)
    }
    @MainActor private func loaded(_ api: EvidenceWorkspaceAPI, exporter: FindingEvidenceExporter? = nil) async throws -> FindingTrafficWorkspace {
        let value = try make(api,exporter:exporter); await value.refresh(); await value.selectBinding("21",owner:value.id); return value
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Controlled operation not reached"); throw CancellationError()
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artex-ui-evidence-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false); return url
    }
    @MainActor private func receipt(_ manifest: FindingEvidenceDownload,_ destination: EvidenceExportDestination) throws -> EvidenceExportReceipt {
        let bytes = manifest.side == .request ? Data() : Data([0,255,97])
        let writer = try EvidenceExportWriter(destination:destination,request:manifest); try writer.append(bytes)
        let result = BackendDownloadResult(status:200,byteCount:Int64(bytes.count),sha256:EvidenceWorkspaceAPI.hash(bytes))
        return try EvidenceExportReceipt(response:.init(result:result,file:writer.finish(response:result)))
    }
    @MainActor func testEvidenceContentRendersBothLocalesAndAppearancesWithoutDispatching() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api), count = api.calls.count
        let presenter = EvidenceSavePanelPresenter()
        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let view = NSHostingView(rootView:FindingTrafficContent(model:model,presenter:presenter,close:{})
                    .environment(\.locale,language.locale).environment(\.colorScheme,scheme))
                view.frame = NSRect(x:0,y:0,width:900,height:640); view.layoutSubtreeIfNeeded()
                XCTAssertTrue(view.fittingSize.width.isFinite); XCTAssertTrue(view.fittingSize.height.isFinite)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
                view.cacheDisplay(in:view.bounds,to:bitmap); XCTAssertGreaterThan(bitmap.pixelsWide,0)
            }
        }
        XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testSavePanelWithoutOwnedWindowDoesNotPresentOrChooseDestination() async {
        let presenter = EvidenceSavePanelPresenter()
        let value = await presenter.choose(suggestedFilename:"evidence-21-response.bin")
        XCTAssertNil(value); presenter.cancel()
    }
    @MainActor func testReadPreservesRawDataAndExplicitPagesWithoutRecordedURLFetch() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api)
        XCTAssertEqual(model.store.summary.value?.bindings.first?.role,"future-role")
        XCTAssertEqual(Array(model.requestHeader.utf8),Array(api.literal.utf8))
        XCTAssertEqual(Array(model.preview(.response)?.content.utf8 ?? "".utf8),Array(api.literal.utf8))
        await model.more(.response,owner:model.id)
        XCTAssertEqual(Array(model.preview(.response)?.content.utf8 ?? "".utf8),Array((api.literal+api.literal).utf8))
        XCTAssertEqual(model.preview(.response)?.nextOffset,3)
        XCTAssertEqual(model.preview(.request)?.content,"")
        await model.more(.response,owner:model.id); await model.more(.request,owner:model.id)
        XCTAssertEqual(api.calls.count,3); XCTAssertTrue(api.calls.last?.contains("offset=1") == true)
        XCTAssertTrue(api.calls.allSatisfy { $0.hasPrefix("/api/exploration/findings/7/traffic") })
    }
    @MainActor func testWrongOwnerAndStoppedWorkspaceNeverDispatchOrRetainBody() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api), count = api.calls.count
        await model.selectBinding("21",owner:UUID()); await model.more(.response,owner:UUID())
        XCTAssertEqual(api.calls.count,count)
        model.stop(); await model.refresh(); await model.selectBinding("21",owner:model.id)
        XCTAssertNil(model.preview(.response)); XCTAssertNil(model.store.summary.value); XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testFailureRetainsLastGoodPageAndRetriesSameOffset() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api)
        api.status = 503; await model.more(.response,owner:model.id)
        XCTAssertNotNil(model.failure); XCTAssertEqual(model.preview(.response)?.nextOffset,1)
        api.status = 200; await model.more(.response,owner:model.id)
        XCTAssertEqual(model.preview(.response)?.nextOffset,3); XCTAssertNil(model.failure)
    }
    @MainActor func testStopWhileReadHeldRejectsLateResponse() async throws {
        let api = EvidenceWorkspaceAPI(), model = try make(api); api.hold = true
        let job = Task { await model.refresh() }; try await wait { api.pending.count == 1 }
        model.stop(); api.pending.removeFirst().resume(returning:try api.response(["finding_id":"7","version":2,"report_version":1,"bindings":[api.binding]]))
        await job.value; XCTAssertNil(model.store.summary.value); XCTAssertFalse(model.isActive)
    }
    @MainActor func testInheritedReadAllowedLegacyRejected() async throws {
        let api = EvidenceWorkspaceAPI(), model = try make(api,inherited:true); await model.refresh()
        XCTAssertNotNil(model.store.summary.value)
        XCTAssertThrowsError(try FindingTrafficWorkspace(target:api.target(legacy:true),service:.init(client:api)))
    }
    @MainActor func testActualSavePublishesVerifiedFileOnlyAfterChooserAndReceipt() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let chooser = EvidenceDestinationFixture(); chooser.url = root.appendingPathComponent("saved.bin")
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ try self.receipt($0,$1) })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { !model.isExporting }
        XCTAssertEqual(try Data(contentsOf:XCTUnwrap(chooser.url)),Data([0,255,97]))
        XCTAssertEqual(model.saved?.byteCount,3); XCTAssertEqual(chooser.names,["evidence-21-response.bin"])
        XCTAssertNil(model.failure); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["saved.bin"])
    }
    @MainActor func testChooserCancelDuplicateWrongOwnerAndUnavailableExportNeverDispatch() async throws {
        let api = EvidenceWorkspaceAPI(); var dispatches = 0
        let model = try await loaded(api,exporter:{ _,_ in dispatches += 1; throw CancellationError() })
        let chooser = EvidenceDestinationFixture(); chooser.hold = true
        XCTAssertFalse(model.startExport(.response,owner:UUID(),chooser:chooser))
        XCTAssertTrue(model.startExport(.request,owner:model.id,chooser:chooser))
        XCTAssertFalse(model.startExport(.response,owner:model.id,chooser:chooser))
        try await wait { chooser.pending != nil }; model.cancelExport(); try await wait { !model.isExporting }
        XCTAssertEqual(dispatches,0); XCTAssertNil(model.saved); XCTAssertNil(model.failure)
        let unavailable = try await loaded(api); XCTAssertFalse(unavailable.startExport(.response,owner:unavailable.id,chooser:chooser))
    }
    @MainActor func testLateReceiptAfterStopIsDiscardedAndCannotPublish() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let chooser = EvidenceDestinationFixture(); chooser.url = root.appendingPathComponent("late.bin")
        var continuation: CheckedContinuation<EvidenceExportReceipt,any Error>?
        var heldReceipt: EvidenceExportReceipt?
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ manifest,destination in
            heldReceipt = try self.receipt(manifest,destination)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { continuation != nil }
        XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(chooser.url).path))
        await model.selectBinding(nil,owner:model.id); XCTAssertEqual(model.store.selectedBindingID,"21")
        model.stop(); continuation?.resume(returning:try XCTUnwrap(heldReceipt)); try await wait { !model.isExporting }
        XCTAssertNil(model.saved); XCTAssertNil(model.failure); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    }
    @MainActor func testSynchronousCancelDuringBusyPublicationCannotStartChooserOrTransfer() async throws {
        let api = EvidenceWorkspaceAPI(); var transfers = 0
        let model = try await loaded(api,exporter:{ _,_ in transfers += 1; throw CancellationError() })
        let chooser = EvidenceDestinationFixture()
        withObservationTracking { _ = model.isExporting } onChange: { MainActor.assumeIsolated { model.cancelExport() } }
        _ = model.startExport(.response,owner:model.id,chooser:chooser)
        try await wait { !model.isExporting }
        XCTAssertEqual(chooser.names,[]); XCTAssertEqual(transfers,0); XCTAssertTrue(model.isActive); XCTAssertNil(model.saved)
    }
    @MainActor func testSynchronousDepartureDuringBusyPublicationNeverOpensChooser() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ _,_ in throw CancellationError() })
        let chooser = EvidenceDestinationFixture()
        withObservationTracking { _ = model.isExporting } onChange: { MainActor.assumeIsolated { model.stop() } }
        _ = model.startExport(.response,owner:model.id,chooser:chooser)
        try await wait { !model.isExporting }
        XCTAssertEqual(chooser.names,[]); XCTAssertFalse(model.isActive); XCTAssertNil(model.saved)
    }
    @MainActor func testSynchronousDepartureDuringPreviewPublicationCannotRestoreBody() async throws {
        let api = EvidenceWorkspaceAPI(), model = try make(api); await model.refresh(); api.hold = true
        let job = Task { await model.selectBinding("21",owner:model.id) }; try await wait { api.pending.count == 1 }
        withObservationTracking { _ = model.preview(.request)?.content } onChange: { MainActor.assumeIsolated { model.stop() } }
        api.pending.removeFirst().resume(returning:try api.response(["binding":api.binding,"request":api.page("",next:0,total:0),"response":api.page(api.literal)]))
        await job.value
        XCTAssertFalse(model.isActive); XCTAssertNil(model.preview(.request)); XCTAssertNil(model.preview(.response))
        XCTAssertEqual(model.requestHeader,""); XCTAssertEqual(model.responseHeader,""); XCTAssertFalse(model.isReading)
    }
    @MainActor func testStopIsSafeUnderBoundedSynchronousReentry() async throws {
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api), witness = ReentrantEvidenceDeparture()
        witness.model = model; witness.arm(); model.stop()
        XCTAssertEqual(witness.changes,1); XCTAssertNil(model.preview(.response)); XCTAssertFalse(model.isActive)
    }
    @MainActor func testMismatchedVerifiedReceiptCannotPublishWrongOriginalBody() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let chooser = EvidenceDestinationFixture(); chooser.url = root.appendingPathComponent("wrong.bin")
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ manifest,destination in
            let wrong = try FindingEvidenceDownload(findingID:manifest.findingID,bindingID:manifest.bindingID,side:.request,expectedSize:0,expectedSHA256:EvidenceWorkspaceAPI.hash(Data()))
            return try self.receipt(wrong,destination)
        })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { !model.isExporting }
        XCTAssertNil(model.saved); XCTAssertNotNil(model.failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(chooser.url).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    }
    @MainActor func testExistingDestinationIsPreservedAndExporterNotDispatched() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("existing.bin"); try Data([44]).write(to:url)
        let chooser = EvidenceDestinationFixture(); chooser.url = url; var calls = 0
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ _,_ in calls += 1; throw CancellationError() })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { !model.isExporting }
        XCTAssertEqual(calls,0); XCTAssertEqual(try Data(contentsOf:url),Data([44])); XCTAssertNotNil(model.failure)
    }
    @MainActor func testExportFailureAndCleanupFailureUseSafeLocalizedMessages() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let chooser = EvidenceDestinationFixture(); chooser.url = root.appendingPathComponent("fail.bin")
        let api = EvidenceWorkspaceAPI(); var cleanup = false
        let model = try await loaded(api,exporter:{ _,_ in
            if cleanup { throw EvidenceExportError.cleanupRequired }
            throw NSError(domain:"private response body secret",code:99)
        })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { !model.isExporting }
        for language in AppLanguage.allCases { XCTAssertFalse(model.failure?.text(language:language).contains("private") ?? true) }
        cleanup = true
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { !model.isExporting }
        XCTAssertEqual(model.failure?.text(language:.english),AppStrings.text(.evidenceUICleanupFailed,language:.english))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    }
    @MainActor func testStoppedChooserCannotStartTransferWithLateApprovedURL() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let chooser = EvidenceDestinationFixture(); chooser.url = root.appendingPathComponent("late.bin"); chooser.hold = true
        var calls = 0
        let api = EvidenceWorkspaceAPI(), model = try await loaded(api,exporter:{ _,_ in calls += 1; throw CancellationError() })
        XCTAssertTrue(model.startExport(.response,owner:model.id,chooser:chooser)); try await wait { chooser.pending != nil }
        let late = chooser.pending; chooser.pending = nil; model.stop()
        late?.resume(returning:chooser.url); try await wait { !model.isExporting }
        XCTAssertEqual(calls,0); XCTAssertNil(model.saved); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),[])
    }
    @MainActor func testBinaryPreviewDoesNotRequestMoreAndInvalidAppendIsRejected() throws {
        let api = EvidenceWorkspaceAPI()
        let raw = try JSONSerialization.data(withJSONObject:api.page(api.literal,binary:true))
        var display = try EvidenceTextPreview(BackendJSONCoding.decode(FindingEvidencePreview.self,from:raw))
        XCTAssertFalse(display.hasMore)
        let wrong = try BackendJSONCoding.decode(FindingEvidencePreview.self,from:JSONSerialization.data(withJSONObject:api.page("wrong",offset:0,next:3)))
        XCTAssertThrowsError(try display.append(wrong)); XCTAssertEqual(display.nextOffset,1)
    }
    @MainActor func testCapturedTrafficDismissBindingCannotCloseReplacementSheet() async throws {
        let api = EvidenceWorkspaceAPI(), parent = FindingScreenModel(store:FindingStore(service:.init(client:api)),trafficService:.init(client:api))
        await parent.store.refreshView(); await parent.selectDetail(id:"7",owner:parent.store.viewOwner)
        XCTAssertTrue(parent.beginTraffic(owner:parent.store.viewOwner,revision:parent.detailRevision))
        let first = try XCTUnwrap(parent.trafficWorkspace), dismiss = FindingBindings.traffic(parent,id:parent.trafficWorkspace?.id)
        parent.closeTraffic(id:first.id)
        XCTAssertTrue(parent.beginTraffic(owner:parent.store.viewOwner,revision:parent.detailRevision))
        let second = try XCTUnwrap(parent.trafficWorkspace); XCTAssertNil(dismiss.wrappedValue); dismiss.wrappedValue = nil
        XCTAssertEqual(parent.trafficWorkspace?.id,second.id); XCTAssertTrue(second.isActive)
        FindingBindings.traffic(parent,id:second.id).wrappedValue = nil; XCTAssertNil(parent.trafficWorkspace)
    }
    @MainActor func testParentDepartureDuringSheetPublicationCannotRestoreActiveWorkspace() async throws {
        let api = EvidenceWorkspaceAPI(), parent = FindingScreenModel(store:FindingStore(service:.init(client:api)),trafficService:.init(client:api))
        await parent.store.refreshView(); await parent.selectDetail(id:"7",owner:parent.store.viewOwner)
        let owner = parent.store.viewOwner, revision = parent.detailRevision
        withObservationTracking { _ = parent.trafficWorkspace } onChange: { MainActor.assumeIsolated { parent.stop() } }
        XCTAssertFalse(parent.beginTraffic(owner:owner,revision:revision))
        XCTAssertNil(parent.trafficWorkspace)
    }
    @MainActor func testParentOwnsSheetAndRejectsOldDismissAndOtherActions() async throws {
        let api = EvidenceWorkspaceAPI(), parent = FindingScreenModel(store:FindingStore(service:.init(client:api)),trafficService:.init(client:api))
        await parent.store.refreshView(); await parent.selectDetail(id:"7",owner:parent.store.viewOwner)
        XCTAssertTrue(parent.beginTraffic(owner:parent.store.viewOwner,revision:parent.detailRevision))
        let first = try XCTUnwrap(parent.trafficWorkspace)
        XCTAssertFalse(parent.controlsAvailable); XCTAssertFalse(parent.configureFilters(.init(search:"other")))
        XCTAssertFalse(parent.beginDelete(try api.target()))
        await parent.closeDetail(owner:parent.store.viewOwner,revision:parent.detailRevision)
        XCTAssertNotNil(parent.store.selectedDetail)
        parent.closeTraffic(id:first.id); XCTAssertFalse(first.isActive); XCTAssertTrue(parent.controlsAvailable)
        XCTAssertTrue(parent.beginTraffic(owner:parent.store.viewOwner,revision:parent.detailRevision))
        let second = try XCTUnwrap(parent.trafficWorkspace); parent.closeTraffic(id:first.id)
        XCTAssertEqual(parent.trafficWorkspace?.id,second.id)
        parent.stop(); XCTAssertNil(parent.trafficWorkspace); XCTAssertFalse(second.isActive)
    }
}
