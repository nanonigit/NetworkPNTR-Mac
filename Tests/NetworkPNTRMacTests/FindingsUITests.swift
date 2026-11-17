import XCTest
import AppKit
import SwiftUI
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor private final class FindingsUIAPI: BackendJSONTransport {
    var paths: [String] = []
    var holdTree = false
    var treeReply: CheckedContinuation<BackendHTTPResponse,Error>?
    var holdWrite = false
    var readStatus = 200
    var writeReply: CheckedContinuation<BackendHTTPResponse,Error>?
    let row = #"{"id":"7","finding_id":"7","name":"\ufeffe\u0301 中文 한국어","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"literal","evidence":"e","report":"report","task_id":"11","ts":"raw"}"#
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path)
        if method != "GET" {
            if holdWrite { return try await withCheckedThrowingContinuation { writeReply = $0 } }
            return .init(status:503,body:Data())
        }
        if readStatus != 200 { return .init(status:readStatus,body:Data()) }
        if path.contains("asset-tree") {
            if holdTree { return try await withCheckedThrowingContinuation { treeReply = $0 } }
            return tree
        }
        if path.contains("/stats") { return reply(#"{"total":1,"pending":1,"critical":0,"high":1,"medium":0,"low":0,"tasks":[],"vulnclasses":["CWE-79"]}"#) }
        if path.contains("/groups") { return reply(#"{"items":[{"task_id":11,"task_name":"literal e\u0301 中文 한국어","task_description":"desc","task_status":"done","count":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"},{"task_id":null,"task_name":"","task_description":"","task_status":"","count":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"}],"total":2,"finding_total":2,"page":1,"page_size":10}"#) }
        if path.hasPrefix("/api/exploration/findings/7") || path.hasPrefix("/api/exploration/findings/8") {
            return reply(path.contains("/8") ? row.replacingOccurrences(of:#""id":"7","finding_id":"7""#,with:#""id":"8","finding_id":"8""#) : row)
        }
        let query = URLComponents(string:path)?.queryItems ?? []
        let page = query.first{$0.name == "page"}?.value ?? "1", size = query.first{$0.name == "limit"}?.value ?? "20"
        var item = row
        if query.contains(where:{$0.name == "task_id" && $0.value == "__unassigned__"}) {
            item = row.replacingOccurrences(of:#""id":"7","finding_id":"7""#,with:#""id":"8","finding_id":"8""#).replacingOccurrences(of:#""task_id":"11""#,with:#""task_id":null"#)
        }
        return reply("{\"items\":[\(item)],\"total\":100,\"page\":\(page),\"page_size\":\(size)}")
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
        XCTAssertEqual(FindingPresentation.time("literal 中文 한국어",language:.japanese),"literal 中文 한국어")
        let time = "2026-10-27T01:23:00.000Z"
        XCTAssertNotEqual(FindingPresentation.time(time,language:.english),time)
        XCTAssertNotEqual(FindingPresentation.time(time,language:.japanese),time)
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
        let (api,screen) = await make(); await screen.store.refreshStats()
        for view in FindingView.allCases {
            XCTAssertTrue(screen.setView(view))
            await screen.store.refreshView()
            if view == .grouped {
                for key in ["11","__unassigned__"] { await screen.store.setGroupExpanded(key,expanded:true,owner:screen.store.viewOwner) }
                XCTAssertEqual(screen.store.groupPages.count,2)
            }
            if view == .asset { screen.expandedAssets = [Data("r:é".utf8)]; XCTAssertEqual(screen.store.tree.value?.nodes.count,2) }
            let before = api.paths.count
            for language in AppLanguage.allCases {
                for scheme in [ColorScheme.light,.dark] {
                    let host = NSHostingView(rootView:FindingsContent(model:screen,onTask:{_ in}).environment(\.locale,language.locale).environment(\.colorScheme,scheme))
                    for width in [900.0,1440.0] { host.frame = NSRect(x:0,y:0,width:width,height:800); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window) }
                }
            }
            XCTAssertEqual(api.paths.count,before)
        }
        screen.stop()
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
        XCTAssertTrue(screen.setView(.flat)); try await reached { !screen.reads.isPending && screen.store.isPolling }
        XCTAssertTrue(screen.store.isPolling,"Flat view must restart polling after the one-shot asset view")
        screen.stop()
        for wait in sleeps { wait.resume(throwing:CancellationError()) }
        let before = api.paths.count; screen.reads.request(forceTree:true)
        await Task.yield(); XCTAssertEqual(api.paths.count,before); XCTAssertFalse(screen.reads.isPending)
    }
    @MainActor func testAllDialogKindsHostInBothLanguagesWithoutDispatching() async throws {
        let (api,screen) = await make(); let row = try XCTUnwrap(screen.store.flat.read.value?.items.first)
        for kind in 0..<4 {
            switch kind {
            case 0: XCTAssertTrue(screen.beginEdit(row))
            case 1: XCTAssertTrue(screen.beginStatus(row,status:.confirmed))
            case 2: XCTAssertTrue(screen.beginDelete(row))
            default:
                _ = await screen.store.delete(row,owner:screen.store.viewOwner)
                XCTAssertTrue(screen.beginAcknowledgement("7"))
            }
            let id = try XCTUnwrap(screen.dialog).id, before = api.paths.count
            for language in AppLanguage.allCases {
                let host = NSHostingView(rootView:FindingDialogView(model:screen,contextID:id).environment(\.locale,language.locale))
                host.frame = NSRect(x:0,y:0,width:560,height:600); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window)
            }
            XCTAssertEqual(api.paths.count,before); screen.close(dialogID:id)
        }
        screen.stop()
    }
    @MainActor func testOldInspectorDismissalAndCloseCannotAffectNewSelectionOrABA() async throws {
        let (_,screen) = await make(); let owner = screen.store.viewOwner
        await screen.selectDetail(id:"7",owner:owner)
        let revision = screen.detailRevision, dismiss = FindingBindings.detail(screen,owner:owner,revision:screen.detailRevision)
        await screen.selectDetail(id:"8",owner:owner); dismiss.wrappedValue = false
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(screen.store.selectedDetail?.id,"8")
        await screen.selectDetail(id:"7",owner:owner); await screen.closeDetail(owner:owner,revision:revision)
        XCTAssertEqual(screen.store.selectedDetail?.id,"7")
        await screen.closeDetail(owner:owner,revision:screen.detailRevision); XCTAssertNil(screen.store.selectedDetail)
    }
    @MainActor func testPendingSearchSurvivesModeAndPageButNotReplacementOrLogout() async {
        let (_,screen) = await make()
        screen.searchDraft = "literal e\u{301} 中文 한국어"; let ticket = screen.searchTicket
        XCTAssertTrue(screen.page(page:2,size:20,owner:screen.store.viewOwner)); XCTAssertTrue(screen.setView(.asset))
        XCTAssertTrue(screen.commitSearch(ticket)); XCTAssertEqual(Array(screen.store.filters.search.utf8),Array("literal e\u{301} 中文 한국어".utf8))
        screen.searchDraft = "newer"; XCTAssertFalse(screen.commitSearch(ticket))
        let next = screen.searchTicket; screen.reset(); XCTAssertFalse(screen.commitSearch(next)); XCTAssertEqual(screen.store.filters.search,"")
    }
    @MainActor func testOldDialogDraftGetterCannotReadNewDialogInputs() async throws {
        let (_,screen) = await make(); let row = try XCTUnwrap(screen.store.flat.read.value?.items.first)
        XCTAssertTrue(screen.beginEdit(row)); let id = try XCTUnwrap(screen.dialog).id
        let draft = FindingBindings.draft(screen,id:id,key:\.nameDraft)
        let severity = FindingBindings.severity(screen,id:id)
        screen.close(dialogID:id); XCTAssertTrue(screen.beginEdit(row)); screen.nameDraft = "new private draft"
        XCTAssertEqual(draft.wrappedValue,""); draft.wrappedValue = "stale"; XCTAssertEqual(screen.nameDraft,"new private draft")
        XCTAssertEqual(severity.wrappedValue,"keep"); severity.wrappedValue = "critical"; XCTAssertEqual(screen.severityDraft,.high)
    }
    @MainActor func testPendingSearchResumesAfterDialogGateAndUsesCurrentFilters() async throws {
        let (_,screen) = await make(); let row = try XCTUnwrap(screen.store.flat.read.value?.items.first)
        screen.searchDraft = "pending literal"; let intent = screen.searchTicket
        XCTAssertTrue(screen.beginEdit(row)); XCTAssertFalse(screen.searchTicket.enabled); XCTAssertFalse(screen.commitSearch(intent))
        screen.close(dialogID:try XCTUnwrap(screen.dialog).id); XCTAssertTrue(screen.searchTicket.enabled)
        XCTAssertTrue(screen.commitSearch(intent)); XCTAssertEqual(screen.store.filters.search,"pending literal")
    }
    @MainActor func testLatestReadAndStatsWaitForHeldWriteAndReactivationWithoutClearingUnknown() async throws {
        let (api,screen) = await make(); let row = try XCTUnwrap(screen.store.flat.read.value?.items.first)
        api.holdWrite = true
        let work = Task { await screen.store.delete(row,owner:screen.store.viewOwner) }
        try await reached { api.writeReply != nil }
        screen.reads.activate(); screen.reads.request(stats:true)
        XCTAssertTrue(screen.reads.isPending); let before = api.paths.count
        for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(api.paths.count,before)
        screen.stop(); screen.reads.activate(); screen.reads.request(stats:true)
        try XCTUnwrap(api.writeReply).resume(returning:.init(status:503,body:Data()))
        _ = await work.value
        try await reached { !screen.reads.isPending && screen.store.stats.value != nil }
        XCTAssertEqual(screen.store.unknownIDs,["7"]); XCTAssertTrue(api.paths.contains{$0.contains("/stats")})
        screen.stop()
    }
    func testIterativeAssetPresentationHandlesDeepValidatedForest() throws {
        let nodes = (0..<4096).map { i -> [String:Any] in
            var node: [String:Any] = ["key":"n:\(i)","kind":"company","label":"literal","self":0,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"]
            if i > 0 { node["parent"] = "n:\(i-1)" }; return node
        }
        let tree = try BackendJSONCoding.decode(FindingAssetTree.self,from:JSONSerialization.data(withJSONObject:["nodes":nodes,"finding_total":1,"truncated":false]))
        let rows = FindingPresentation.assetRows(tree,expanded:Set(nodes.compactMap{($0["key"] as? String).map{Data($0.utf8)}}))
        XCTAssertEqual(rows.count,4096); XCTAssertEqual(rows.last?.depth,4095)
    }
    @MainActor func testDetailReadOnlyProvenanceAndFailureNoticesHostWithoutExtraRequests() async throws {
        let (api,screen) = await make()
        for variant in 0..<3 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(api.row.utf8)) as? [String:Any])
            object["report_stale"] = true
            if variant == 1 { object["inherited"] = true; object["source_task_id"] = "11" }
            if variant == 2 { object["finding_id"] = NSNull(); object["status"] = "literal 中文 한국어" }
            let row = try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:object))
            await screen.store.detail.refresh { row }
            let before = api.paths.count
            for language in AppLanguage.allCases {
                let host = NSHostingView(rootView:FindingDetailPanel(model:screen,onTask:{_ in}).environment(\.locale,language.locale))
                host.frame = NSRect(x:0,y:0,width:360,height:800); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window)
            }
            XCTAssertEqual(api.paths.count,before); if variant > 0 { XCTAssertFalse(screen.beginEdit(row)) }
        }
        api.readStatus = 503; await screen.store.refreshView(); await screen.store.refreshStats()
        XCTAssertTrue(screen.store.flat.read.isStale); XCTAssertNotNil(screen.store.flat.read.failure)
        let before = api.paths.count
        let host = NSHostingView(rootView:FindingsContent(model:screen,onTask:{_ in}).environment(\.locale,AppLanguage.japanese.locale))
        host.frame = NSRect(x:0,y:0,width:1200,height:800); host.layoutSubtreeIfNeeded(); XCTAssertEqual(api.paths.count,before)
        screen.stop()
    }
    @MainActor func testFilterAndPagerBindingsPreserveRawValuesAndRejectStaleOrDialogOwners() async throws {
        let (api,screen) = await make(); let owner = screen.store.viewOwner
        let filter = FindingBindings.filter(screen,owner:owner,get:{$0.vulnclass},set:{$0.vulnclass = $1})
        let literal = "literal e\u{301} 中文 한국어"; filter.wrappedValue = literal
        XCTAssertEqual(Array(screen.store.filters.vulnclass.utf8),Array(literal.utf8)); filter.wrappedValue = "stale"; XCTAssertEqual(screen.store.filters.vulnclass,literal)
        XCTAssertFalse(screen.page(page:2,size:20,owner:owner)); XCTAssertTrue(screen.page(page:2,size:50,owner:screen.store.viewOwner))
        XCTAssertEqual(screen.store.flat.page,2)
        screen.expandedAssets = [Data("literal".utf8)]; XCTAssertTrue(screen.configureFilters(screen.store.filters)); XCTAssertFalse(screen.expandedAssets.isEmpty)
        XCTAssertTrue(screen.setView(.grouped)); await screen.store.refreshView()
        await screen.store.setGroupExpanded("11",expanded:true,owner:screen.store.viewOwner)
        XCTAssertTrue(screen.page(page:2,size:20,owner:screen.store.viewOwner,group:"11")); XCTAssertEqual(screen.store.groupPages["11"]?.page,2)
        let count = api.paths.count; screen.reads.request(); XCTAssertEqual(api.paths.count,count)
        XCTAssertTrue(screen.setView(.flat)); await screen.store.refreshView()
        let row = try XCTUnwrap(screen.store.flat.read.value?.items.first); XCTAssertTrue(screen.beginEdit(row))
        XCTAssertFalse(screen.page(page:3,size:20,owner:screen.store.viewOwner)); screen.stop()
    }
    func testOnlyGeneratedUnassignedAssetLabelIsLocalizedAndRawDataIsPreserved() throws {
        let tree = try BackendJSONCoding.decode(FindingAssetTree.self,from:Data(#"{"nodes":[{"key":"__none__","kind":"none","label":"未关联资产","self":0,"total":0,"critical":0,"high":0,"medium":0,"low":0,"last_found_at":"raw"},{"key":"c:8200","kind":"company","label":"literal e\u0301 中文 한국어","self":0,"total":0,"critical":0,"high":0,"medium":0,"low":0,"last_found_at":"raw"},{"key":"custom:none","kind":"none","label":"custom 中文 한국어","self":0,"total":0,"critical":0,"high":0,"medium":0,"low":0,"last_found_at":"raw"}],"finding_total":0,"truncated":false}"#.utf8))
        let original = Array(tree.nodes[0].label.utf8)
        XCTAssertEqual(FindingPresentation.assetLabel(tree.nodes[0],language:.english),"Unassigned assets")
        XCTAssertEqual(FindingPresentation.assetLabel(tree.nodes[0],language:.japanese),"未関連の資産")
        XCTAssertEqual(Array(tree.nodes[0].label.utf8),original)
        for node in tree.nodes.dropFirst() { for language in AppLanguage.allCases {
            XCTAssertEqual(Array(FindingPresentation.assetLabel(node,language:language).utf8),Array(node.label.utf8))
        } }
    }
}
