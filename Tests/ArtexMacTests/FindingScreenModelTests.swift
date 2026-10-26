import XCTest
import ArtexCore
@testable import ArtexMac

@MainActor private final class FindingScreenAPI: BackendJSONTransport {
    var methods: [String] = []
    var bodies: [Data?] = []
    var hold = false
    var held: CheckedContinuation<BackendHTTPResponse,Error>?
    var response = BackendHTTPResponse(status:503,body:Data())
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        methods.append(method); bodies.append(body)
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        return response
    }
}

final class FindingScreenModelTests: XCTestCase {
    private func row(name: String = "literal e\u{301} 中文 한국어", inherited: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject:["id":"7","finding_id":"7","name":name,"vulnclass":"CWE-79","severity":"high","status":"pending","summary":"s","evidence":"e","report":"r","task_id":"11","source_task_id":"11","inherited":inherited,"ts":"raw"])
    }
    @MainActor private func ready(_ api: FindingScreenAPI) async throws -> FindingScreenModel {
        let item = try JSONSerialization.jsonObject(with:row())
        api.response = .init(status:200,body:try JSONSerialization.data(withJSONObject:["items":[item],"total":1,"page":1,"page_size":20]))
        let screen = FindingScreenModel(store:FindingStore(service:FindingService(client:api)))
        await screen.store.refreshView(); return screen
    }
    @MainActor private func target(_ screen: FindingScreenModel) throws -> FindingRecord { try XCTUnwrap(screen.store.flat.read.value?.items.first) }
    @MainActor private func submit(_ screen: FindingScreenModel) async -> Bool {
        guard let id = screen.dialog?.id else { XCTFail("Missing dialog"); return false }
        return await screen.submit(dialogID:id)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled handoff"); throw CancellationError()
    }
    @MainActor func testCapturedEditPreservesLiteralDraftAndConfirmedReceipt() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api)
        XCTAssertTrue(screen.beginEdit(try target(screen)))
        XCTAssertEqual(Array(screen.nameDraft.utf8),Array(try target(screen).name.utf8))
        screen.nameDraft = " \u{FEFF}changed e\u{301} 中文 한국어\u{FEFF} "
        api.response = .init(status:200,body:try row(name:"changed e\u{301} 中文 한국어"))
        let saved = await submit(screen); XCTAssertTrue(saved); XCTAssertNil(screen.dialog)
        XCTAssertEqual(api.methods,["GET","PATCH"]); XCTAssertNotNil(screen.store.lastConfirmation)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(api.bodies.last!)) as? [String:Any])
        XCTAssertEqual(Array(try XCTUnwrap(body["name"] as? String).utf8),Array("changed e\u{301} 中文 한국어".utf8))
    }
    @MainActor func testOldViewDialogNeverSubstitutesFreshOwner() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api)
        XCTAssertTrue(screen.beginDelete(try target(screen))); let id = try XCTUnwrap(screen.dialog).id
        XCTAssertTrue(screen.store.configureFilters(.init(search:"new")))
        let saved = await screen.submit(dialogID:id); XCTAssertFalse(saved); XCTAssertEqual(api.methods,["GET"])
    }
    @MainActor func testFailureIsUncertainAndCannotReplayBySubmittingOrReopening() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api); let record = try target(screen)
        XCTAssertTrue(screen.beginDelete(record)); api.response = .init(status:400,body:Data())
        let saved = await submit(screen); XCTAssertFalse(saved); XCTAssertTrue(screen.dialogUncertain)
        let repeated = await submit(screen); XCTAssertFalse(repeated); XCTAssertEqual(api.methods,["GET","DELETE"])
        screen.close(dialogID:try XCTUnwrap(screen.dialog).id)
        XCTAssertFalse(screen.beginDelete(record)); XCTAssertEqual(screen.store.unknownIDs,["7"])
    }
    @MainActor func testAcknowledgementCapturesEpisodeAndCannotClearNewerSameID() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api); let record = try target(screen)
        api.response = .init(status:500,body:Data()); _ = await screen.store.delete(record,owner:screen.store.viewOwner)
        XCTAssertTrue(screen.beginAcknowledgement("7")); let old = try XCTUnwrap(screen.dialog)
        XCTAssertTrue(screen.store.acknowledgeUnknown("7",owner:screen.store.sessionOwner,revision:screen.store.unknownRevision))
        _ = await screen.store.delete(record,owner:screen.store.viewOwner)
        let accepted = await screen.submit(dialogID:old.id); XCTAssertFalse(accepted); XCTAssertEqual(screen.store.unknownIDs,["7"])
        screen.close(dialogID:old.id); XCTAssertTrue(screen.beginAcknowledgement("7"))
        let current = await submit(screen); XCTAssertTrue(current); XCTAssertTrue(screen.store.unknownIDs.isEmpty)
        XCTAssertEqual(api.methods,["GET","DELETE","DELETE"])
    }
    @MainActor func testStopRetainsInputsButInvalidatesDialogAndHeldWriteGate() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api); let record = try target(screen)
        screen.searchDraft = "literal 中文 한국어"; XCTAssertTrue(screen.beginDelete(record)); api.hold = true
        let work = Task { await self.submit(screen) }; try await reached { api.held != nil }
        XCTAssertTrue(screen.busy); screen.stop(); XCTAssertNil(screen.dialog); XCTAssertTrue(screen.busy)
        XCTAssertEqual(screen.searchDraft,"literal 中文 한국어"); XCTAssertFalse(screen.beginDelete(record))
        try XCTUnwrap(api.held).resume(returning:.init(status:200,body:Data(#"{"deleted":true,"id":7}"#.utf8)))
        let saved = await work.value; XCTAssertFalse(saved); XCTAssertFalse(screen.busy); XCTAssertEqual(screen.store.unknownIDs,["7"])
    }
    @MainActor func testResetClearsPrivateDraftsButKeepsDispatchedGateUntilTerminal() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api); let record = try target(screen)
        XCTAssertTrue(screen.beginEdit(record)); screen.nameDraft = "private"; screen.searchDraft = "secret"; api.hold = true
        let work = Task { await self.submit(screen) }; try await reached { api.held != nil }
        screen.reset(); XCTAssertTrue(screen.busy); XCTAssertNil(screen.dialog); XCTAssertEqual(screen.nameDraft,""); XCTAssertEqual(screen.searchDraft,"")
        try XCTUnwrap(api.held).resume(returning:.init(status:200,body:try row(name:"private")))
        let saved = await work.value; XCTAssertFalse(saved); XCTAssertTrue(screen.store.unknownIDs.isEmpty); XCTAssertFalse(screen.busy)
    }
    @MainActor func testReadOnlyOrUnavailableRecordCannotOpenMutation() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api)
        let inherited = try BackendJSONCoding.decode(FindingRecord.self,from:row(inherited:true))
        XCTAssertFalse(screen.beginEdit(inherited)); XCTAssertFalse(screen.beginDelete(inherited))
        screen.store.reset(); XCTAssertFalse(screen.beginDelete(try BackendJSONCoding.decode(FindingRecord.self,from:row())))
        XCTAssertEqual(api.methods,["GET"])
    }
    @MainActor func testPreferenceRoundTripExcludesPrivateAndTransientValues() throws {
        let suite = "finding-screen-test-"+UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let api = FindingScreenAPI(), screen = FindingScreenModel(store:FindingStore(service:FindingService(client:api)),preferences:defaults)
        XCTAssertTrue(screen.configureFilters(.init(severity:.high,status:.confirmed,vulnclass:"literal e\u{301} 中文 한국어",task:"11",search:"private",sort:.time)))
        XCTAssertTrue(screen.setView(.asset)); _ = screen.store.configureFlat(page:3,size:50)
        let restored = FindingScreenModel(store:FindingStore(service:FindingService(client:api)),preferences:defaults)
        XCTAssertEqual(restored.store.view,.asset); XCTAssertEqual(restored.store.filters.severity,.high); XCTAssertEqual(restored.store.filters.status,.confirmed)
        XCTAssertEqual(Array(restored.store.filters.vulnclass.utf8),Array(screen.store.filters.vulnclass.utf8)); XCTAssertEqual(restored.store.filters.task,"11"); XCTAssertEqual(restored.store.filters.sort,.time)
        XCTAssertEqual(restored.store.filters.search,""); XCTAssertEqual(restored.searchDraft,""); XCTAssertEqual(restored.store.flat.page,1); XCTAssertEqual(restored.store.flat.size,20)
        XCTAssertTrue(restored.store.selectedIDs.isEmpty); XCTAssertNil(restored.store.assetScope); XCTAssertTrue(api.methods.isEmpty)
        let data = try XCTUnwrap(defaults.data(forKey:FindingScreenModel.preferenceKey)); XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("private"))
    }
    @MainActor func testCorruptOversizedOrUnsupportedPreferencesCannotConfigureOrRequest() throws {
        let suite = "finding-screen-test-"+UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let api = FindingScreenAPI()
        for data in [Data("invalid".utf8),Data(repeating:32,count:32769),Data(#"{"version":99,"view":"asset","sort":"time"}"#.utf8),Data(#"{"version":1,"view":"asset","sort":"time","task":"-1"}"#.utf8)] {
            defaults.set(data,forKey:FindingScreenModel.preferenceKey)
            let screen = FindingScreenModel(store:FindingStore(service:FindingService(client:api)),preferences:defaults)
            XCTAssertEqual(screen.store.view,.flat); XCTAssertEqual(screen.store.filters.task,"all"); XCTAssertTrue(api.methods.isEmpty)
        }
    }
    @MainActor func testDialogBlocksFilterPreferenceChangesAndWrongIDCannotDismiss() async throws {
        let api = FindingScreenAPI(), screen = try await ready(api)
        XCTAssertTrue(screen.beginEdit(try target(screen))); let dialog = try XCTUnwrap(screen.dialog)
        XCTAssertFalse(screen.configureFilters(.init(search:"other"))); XCTAssertFalse(screen.setView(.asset))
        screen.close(dialogID:UUID()); XCTAssertEqual(screen.dialog?.id,dialog.id)
        let saved = await screen.submit(dialogID:UUID()); XCTAssertFalse(saved); XCTAssertEqual(api.methods,["GET"])
        screen.close(dialogID:dialog.id); XCTAssertTrue(screen.setView(.asset))
    }
}
