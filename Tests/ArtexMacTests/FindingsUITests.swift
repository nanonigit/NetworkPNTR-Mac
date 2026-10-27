import XCTest
import AppKit
import SwiftUI
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class FindingsUIAPI: BackendJSONTransport {
    var paths: [String] = []
    var holdTree = false
    var treeReply: CheckedContinuation<BackendHTTPResponse,Error>?
    let row = #"{"id":"7","finding_id":"7","name":"\ufeffe\u0301 中文 한국어","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"literal","evidence":"e","report":"report","task_id":"11","ts":"raw"}"#
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path)
        if path.contains("asset-tree") {
            if holdTree { return try await withCheckedThrowingContinuation { treeReply = $0 } }
            return tree
        }
        if path.contains("/stats") { return reply(#"{"total":1,"pending":1,"critical":0,"high":1,"medium":0,"low":0,"tasks":[],"vulnclasses":["CWE-79"]}"#) }
        if path.contains("/groups") { return reply(#"{"items":[],"total":0,"finding_total":0,"page":1,"page_size":10}"#) }
        if !path.contains("?") { return reply(row) }
        let query = URLComponents(string:path)?.queryItems ?? []
        let page = query.first{$0.name == "page"}?.value ?? "1", size = query.first{$0.name == "limit"}?.value ?? "20"
        return reply("{\"items\":[\(row)],\"total\":100,\"page\":\(page),\"page_size\":\(size)}")
    }
    var tree: BackendHTTPResponse { reply(#"{"nodes":[{"key":"r:é","kind":"root_domain","label":"é","self":1,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"},{"key":"r:e\u0301","parent":"r:é","kind":"domain","label":"e\u0301","self":1,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"}],"finding_total":1,"truncated":false}"#) }
    func reply(_ text: String) -> BackendHTTPResponse { .init(status:200,body:Data(text.utf8)) }
}

final class FindingsUITests: XCTestCase {
    @MainActor private func make() async -> (FindingsUIAPI,FindingScreenModel) {
        let api = FindingsUIAPI()
        let screen = FindingScreenModel(store:FindingStore(service:FindingService(client:api)))
        await screen.store.refreshView(); return (api,screen)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled state"); throw CancellationError()
    }
    @MainActor func testCapturedCheckboxAndDialogDismissBindingsRejectStaleOwners() async throws {
        let (_,screen) = await make(), owner = screen.store.viewOwner
        let check = FindingBindings.selected(screen,id:"7",owner:owner); check.wrappedValue = true
        XCTAssertEqual(screen.store.selectedIDs,["7"])
        XCTAssertTrue(screen.beginEdit(try XCTUnwrap(screen.store.flat.read.value?.items.first)))
        let old = try XCTUnwrap(screen.dialog).id, dismiss = FindingBindings.dialog(screen,id:old)
        check.wrappedValue = false; XCTAssertEqual(screen.store.selectedIDs,["7"])
        screen.close(dialogID:old); XCTAssertTrue(screen.beginDelete(try XCTUnwrap(screen.store.flat.read.value?.items.first)))
        let next = screen.dialog?.id; dismiss.wrappedValue = nil; XCTAssertEqual(screen.dialog?.id,next)
        screen.stop(); check.wrappedValue = false; XCTAssertEqual(screen.store.selectedIDs,["7"])
    }
    func testIterativeAssetRowsPreserveCanonicalEquivalentKeysAndExpansion() throws {
        let tree = try BackendJSONCoding.decode(FindingAssetTree.self,from:Data(#"{"nodes":[{"key":"r:é","kind":"root_domain","label":"root","self":0,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"},{"key":"r:e\u0301","parent":"r:é","kind":"domain","label":"child","self":1,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"}],"finding_total":1,"truncated":false}"#.utf8))
        XCTAssertEqual(FindingPresentation.assetRows(tree,expanded:[]).count,1)
        let rows = FindingPresentation.assetRows(tree,expanded:[Data("r:é".utf8)])
        XCTAssertEqual(rows.count,2); XCTAssertNotEqual(rows[0].id,rows[1].id); XCTAssertEqual(rows.map(\.depth),[0,1])
        XCTAssertEqual(FindingPresentation.pages(total:Int64.max,size:100),92233720368547759)
        XCTAssertEqual(FindingPresentation.status("literal 中文 한국어",language:.english),"literal 中文 한국어")
    }
    @MainActor func testLatestAssetScopeAndPageReadWaitsForHeldTreeWithoutCancellingSnapshot() async throws {
        let (api,screen) = await make(); XCTAssertTrue(screen.setView(.asset)); api.holdTree = true
        screen.reads.activate(); screen.reads.request()
        try await reached { api.treeReply != nil }
        // F2 allows page changes while the same-filter tree is still loading.
        XCTAssertTrue(screen.page(page:2,size:20,owner:screen.store.viewOwner)); XCTAssertTrue(screen.store.tree.isLoading)
        try XCTUnwrap(api.treeReply).resume(returning:api.tree)
        try await reached { !screen.reads.isPending }
        XCTAssertEqual(api.paths.filter{$0.contains("asset-tree")}.count,1)
        XCTAssertEqual(screen.store.flat.read.value?.page,2); XCTAssertNotNil(screen.store.tree.value)
        XCTAssertTrue(screen.asset("r:e\u{301}",owner:screen.store.viewOwner))
        try await reached { !screen.reads.isPending }
        XCTAssertEqual(api.paths.filter{$0.contains("asset-tree")}.count,1)
        XCTAssertTrue(api.paths.last?.contains("asset_scope=") == true); screen.stop()
    }
    @MainActor func testOffscreenEnglishJapaneseViewsDoNotStartReadsOrMutations() async throws {
        let (api,screen) = await make(); await screen.store.refreshStats(); let before = api.paths.count
        for view in FindingView.allCases {
            XCTAssertTrue(screen.setView(view))
            for language in AppLanguage.allCases {
                for scheme in [ColorScheme.light,.dark] {
                    let host = NSHostingView(rootView:FindingsContent(model:screen,onTask:{_ in}).environment(\.locale,language.locale).environment(\.colorScheme,scheme))
                    for width in [900.0,1440.0] { host.frame = NSRect(x:0,y:0,width:width,height:800); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window) }
                }
            }
        }
        XCTAssertEqual(api.paths.count,before); screen.stop()
    }
    func testOwnedFindingLabelsAreEnglishJapaneseAndComplete() {
        let keys = AppStringKey.allCases.filter{$0.rawValue.hasPrefix("finding.ui.")}
        XCTAssertGreaterThan(keys.count,40)
        for key in keys { for language in AppLanguage.allCases {
            let value = AppStrings.text(key,language:language); XCTAssertNotEqual(value,key.rawValue); XCTAssertFalse(value.isEmpty)
            XCTAssertFalse(value.unicodeScalars.contains{(0xAC00...0xD7AF).contains($0.value)})
        } }
        for status in FindingStatus.allCases { XCTAssertNotEqual(FindingPresentation.status(status.rawValue,language:.japanese),status.rawValue) }
    }
    @MainActor func testReturningFromAssetRestartsViewPollingAndStopRetainsNoNewWork() async throws {
        let api = FindingsUIAPI()
        var sleeps: [CheckedContinuation<Void,Error>] = []
        let screen = FindingScreenModel(store:FindingStore(service:FindingService(client:api),sleep:{ _ in
            try await withCheckedThrowingContinuation { sleeps.append($0) }
        }))
        XCTAssertTrue(screen.setView(.asset)); screen.reads.activate(); screen.reads.request()
        try await reached { !screen.reads.isPending && screen.store.tree.value != nil }
        XCTAssertFalse(screen.store.isPolling)
        XCTAssertTrue(screen.setView(.flat)); try await reached { !screen.reads.isPending }
        XCTAssertTrue(screen.store.isPolling,"Flat view must restart polling after the one-shot asset view")
        screen.stop()
        for wait in sleeps { wait.resume(throwing:CancellationError()) }
        let before = api.paths.count; screen.reads.request(forceTree:true)
        await Task.yield(); XCTAssertEqual(api.paths.count,before); XCTAssertFalse(screen.reads.isPending)
    }
}
