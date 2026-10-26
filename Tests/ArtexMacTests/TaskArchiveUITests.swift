import XCTest
import AppKit
import SwiftUI
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class ArchiveUIAPI: BackendJSONTransport {
    var calls: [String] = []
    var rows: [String] = []
    var tasks: [[String:Any]] = []
    var holdTasks = false
    var heldTasks: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    var write = BackendHTTPResponse(status:503,body:Data())
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append(method+" "+path)
        if method != "GET" { return write }
        if path == "/api/tasks", holdTasks { return try await withCheckedThrowingContinuation { heldTasks.append($0) } }
        if path == "/api/tasks" { return .init(status:200,body:try JSONSerialization.data(withJSONObject:["tasks":tasks,"active":"7"])) }
        if path.hasPrefix("/api/task-archives?") {
            let items = URLComponents(string:path)?.queryItems ?? []
            let page = items.first{$0.name == "page"}?.value ?? "1", size = items.first{$0.name == "size"}?.value ?? "20"
            return .init(status:200,body:Data("{\"items\":[\(rows.joined(separator:","))],\"total\":101,\"page\":\(page),\"size\":\(size)}".utf8))
        }
        return .init(status:404,body:Data())
    }
}
final class TaskArchiveUITests: XCTestCase {
    private func row(_ id: Int64 = 17, state: String = "ready", counts: String = #"{"rows":9223372036854775807,"more":9223372036854775807}"#) -> String {
        """
        {"id":\(id),"task_id":7,"state":"\(state)","phase":"queued","progress":50,"error":"private 한국어","warnings":["private 中文"],"format_version":3,"original_size":1024,"compressed_size":512,"task_name":"\\ufeffe\\u0301 中文 한국어","task_description":"literal description","task_goal":"g","original_status":"paused","remaining_timeout_seconds":0,"data_counts":\(counts),"requested_at":"2026-10-26T00:00:00Z","created_at":"c","updated_at":"u"}
        """
    }
    @MainActor private func make() async throws -> (ArchiveUIAPI,TaskScreenModel) {
        let api = ArchiveUIAPI(); api.rows = [row(),row(18,state:"restoring")]
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); var task = try XCTUnwrap(root["task"] as? [String:Any]); task["id"] = "7"; task["status"] = "paused"; task["archive_blocked_by_task_id"] = ""; api.tasks = [task]
        let screen = TaskScreenModel(store:TaskStore(service:TaskService(client:api)),bulkService:TaskService(client:api),archiveService:TaskArchiveService(client:api))
        await screen.store.refreshList(); await screen.archives?.refresh(); return (api,screen)
    }
    @MainActor func testCapturedCheckboxAndDialogBindingsIgnoreStaleOwners() async throws {
        let (_,screen) = try await make(); let archives = try XCTUnwrap(screen.archives), actions = try XCTUnwrap(screen.archiveActions)
        let old = TaskArchiveBindings.selected(screen:screen,id:17,owner:archives.viewOwner); old.wrappedValue = true; XCTAssertEqual(archives.selectedIDs,Set([17]))
        XCTAssertTrue(screen.beginArchivedAction(.delete,records:try XCTUnwrap(archives.list.value).items)); let first = try XCTUnwrap(actions.context).id
        let dismiss = TaskArchiveBindings.presentation(model:actions,contextID:first)
        old.wrappedValue = false; XCTAssertEqual(archives.selectedIDs,Set([17]))
        actions.close(contextID:first); XCTAssertTrue(screen.beginArchivedAction(.restore,records:try XCTUnwrap(archives.list.value).items)); let next = try XCTUnwrap(actions.context).id
        dismiss.wrappedValue = nil; XCTAssertEqual(actions.context?.id,next); actions.close(contextID:next)
        screen.stop(); old.wrappedValue = false; XCTAssertEqual(archives.selectedIDs,Set([17]))
    }
    @MainActor func testFiltersResetPagePreserveBytesAndRejectStaleBinding() async throws {
        let (_,screen) = try await make(); XCTAssertTrue(screen.setTaskTab(.archived)); let archives = try XCTUnwrap(screen.archives)
        XCTAssertTrue(screen.configureArchives(page:3,size:20,query:"literal",state:nil,owner:archives.viewOwner))
        let owner = archives.viewOwner
        XCTAssertTrue(screen.configureArchives(page:1,size:50,query:"a+ e\u{301} 中文 한국어",state:"ready",owner:owner))
        XCTAssertFalse(screen.configureArchives(page:2,size:20,query:"stale",state:nil,owner:owner))
        XCTAssertEqual(archives.page,1); XCTAssertEqual(Array(archives.query.utf8),Array("a+ e\u{301} 中文 한국어".utf8)); XCTAssertEqual(archives.size,50)
        screen.stop()
    }
    func testPresentationTotalsAndPagerDoNotOverflowOrLoseUserText() throws {
        let record = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row().utf8))
        XCTAssertEqual(NSDecimalNumber(decimal:TaskArchivePresentation.dataTotal([record,record])).stringValue,"36893488147419103228")
        XCTAssertEqual(TaskArchivePresentation.pages(total:Int64.max,size:50),184467440737095517)
        XCTAssertEqual(TaskArchivePresentation.pages(total:0,size:20),1)
        XCTAssertEqual(Array(TaskArchivePresentation.title(record,language:.english).utf8),Array("\u{feff}e\u{301} 中文 한국어".utf8))
        for language in AppLanguage.allCases {
            XCTAssertFalse(TaskArchivePresentation.compression(record,language:language).contains("private"))
            XCTAssertTrue(TaskArchivePresentation.compression(record,language:language).contains("50"))
        }
    }
    @MainActor func testOffscreenArchiveTableAndEveryActionSheetKeepOwnersAndDoNotSend() async throws {
        let (api,screen) = try await make(); let archives = try XCTUnwrap(screen.archives), actions = try XCTUnwrap(screen.archiveActions), records = try XCTUnwrap(archives.list.value).items
        let before = api.calls.count
        for language in AppLanguage.allCases {
            let host = NSHostingView(rootView:TaskArchivePanel(screen:screen,model:archives).environment(\.locale,language.locale))
            host.frame = NSRect(x:0,y:0,width:1250,height:750); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window); XCTAssertTrue(host.fittingSize.width.isFinite)
        }
        for kind: TaskArchiveActionKind in [.restore,.delete,.retry] {
            let rows = kind == .retry ? [try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row(state:"archive_failed").utf8))] : records
            XCTAssertTrue(screen.beginArchivedAction(kind,records:rows)); let owner = try XCTUnwrap(actions.context).id
            for language in AppLanguage.allCases {
                let host = NSHostingView(rootView:TaskArchiveActionView(model:actions,contextID:owner).environment(\.locale,language.locale))
                host.frame = NSRect(x:0,y:0,width:620,height:600); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window); XCTAssertEqual(actions.context?.id,owner)
            }
            actions.close(contextID:owner)
        }
        XCTAssertEqual(api.calls.count,before); screen.stop()
    }
    @MainActor func testAcceptedLiveArchiveSwitchesTabAndRestore404RefreshIsReadOnly() async throws {
        let (api,screen) = try await make(); let actions = try XCTUnwrap(screen.archiveActions), archives = try XCTUnwrap(screen.archives)
        XCTAssertTrue(screen.beginArchive(try XCTUnwrap(screen.store.list.value?.first)))
        api.write = .init(status:202,body:Data(row(state:"archive_queued").utf8)); _ = await actions.submit(contextID:try XCTUnwrap(actions.context).id)
        XCTAssertEqual(screen.taskTab,.archived); XCTAssertFalse(screen.setTaskTab(.live))
        actions.close(contextID:try XCTUnwrap(actions.context).id)
        let receipt = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row(state:"restore_queued").utf8)); XCTAssertTrue(archives.observeAcceptedRestore(receipt,owner:archives.sessionOwner))
        await archives.refresh(); screen.archiveReconciled()
        for _ in 0..<10000 { if !screen.isRefreshingAfterArchive { break }; await Task.yield() }
        XCTAssertEqual(api.calls.filter{!$0.hasPrefix("GET")}.count,1)
        XCTAssertTrue(archives.removedAfterRestoreIDs.contains(17)); XCTAssertTrue(screen.setTaskTab(.live)); screen.reset(); XCTAssertEqual(screen.taskTab,.live)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled suspension"); throw CancellationError()
    }
    @MainActor func testOverlappingRestoreNoticeRerunsHeldLiveRefresh() async throws {
        let (api,screen) = try await make(); let actions = try XCTUnwrap(screen.archiveActions), archives = try XCTUnwrap(screen.archives)
        api.holdTasks = true
        XCTAssertTrue(screen.beginArchive(try XCTUnwrap(screen.store.list.value?.first)))
        api.write = .init(status:202,body:Data(row(state:"archive_queued").utf8))
        _ = await actions.submit(contextID:try XCTUnwrap(actions.context).id)
        try await reached { api.heldTasks.count == 1 }
        XCTAssertTrue(archives.observeAcceptedRestore(try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row(state:"restore_queued").utf8)),owner:archives.sessionOwner))
        await archives.refresh(); screen.archiveReconciled()
        api.heldTasks[0].resume(returning:.init(status:200,body:try JSONSerialization.data(withJSONObject:["tasks":api.tasks,"active":"7"])))
        try await reached { api.heldTasks.count == 2 }
        api.tasks[0]["name"] = "refreshed after restore"
        api.heldTasks[1].resume(returning:.init(status:200,body:try JSONSerialization.data(withJSONObject:["tasks":api.tasks,"active":"7"])))
        try await reached { !screen.isRefreshingAfterArchive }
        XCTAssertEqual(screen.store.list.value?.first?.name,"refreshed after restore"); screen.stop()
    }

}
