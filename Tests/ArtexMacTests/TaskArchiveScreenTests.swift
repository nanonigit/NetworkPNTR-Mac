import XCTest
import ArtexCore
@testable import ArtexMac

@MainActor private final class ArchiveScreenAPI: BackendJSONTransport {
    var calls = 0
    var tasks: [[String:Any]] = []
    var writeReply = BackendHTTPResponse(status:503,body:Data())
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        if method == "GET", path == "/api/tasks" { return .init(status:200,body:try JSONSerialization.data(withJSONObject:["tasks":tasks,"active":"7"])) }
        return writeReply
    }
}
final class TaskArchiveScreenTests: XCTestCase {
    @MainActor func testWindowRetainsArchiveStateAcrossStopButSessionResetClearsReceipts() async throws {
        let api = ArchiveScreenAPI()
        let screen = TaskScreenModel(store:TaskStore(service:TaskService(client:api)),archiveService:TaskArchiveService(client:api))
        let archives = try XCTUnwrap(screen.archives); let session = archives.sessionOwner
        XCTAssertTrue(archives.configure(page:2,size:10,query:"literal 中文 한국어 e\u{301}",state:"ready"))
        let receipt = try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data("""
        {"id":7,"task_id":8,"state":"restore_queued","phase":"queued","progress":0,"format_version":3,"original_size":0,"compressed_size":0,"task_name":"literal","task_description":"","task_goal":"","original_status":"paused","remaining_timeout_seconds":0,"requested_at":"r","created_at":"c","updated_at":"u"}
        """.utf8))
        XCTAssertTrue(archives.observeAcceptedRestore(receipt,owner:session))
        screen.stop(); XCTAssertTrue(screen.archives === archives); XCTAssertEqual(archives.page,2)
        XCTAssertEqual(archives.pendingRestoreIDs,Set([7])); XCTAssertEqual(api.calls,0)
        screen.reset(); XCTAssertTrue(screen.archives === archives); XCTAssertEqual(archives.page,1)
        XCTAssertTrue(archives.pendingRestoreIDs.isEmpty); XCTAssertNotEqual(archives.sessionOwner,session)
        XCTAssertEqual(api.calls,0)
    }
    @MainActor func testOptionalServicePreservesExistingConstruction() {
        let api = ArchiveScreenAPI(); let screen = TaskScreenModel(store:TaskStore(service:TaskService(client:api)))
        XCTAssertNil(screen.archives); screen.stop(); screen.reset(); XCTAssertEqual(api.calls,0)
    }
    @MainActor func testArchiveActionsShareScreenBusyAndValidBulkReceiptClearsMainSelection() async throws {
        let api = ArchiveScreenAPI()
        let path = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        var row = try XCTUnwrap(object["task"] as? [String:Any]); row["id"] = "7"; row["status"] = "paused"; row["archive_blocked_by_task_id"] = ""
        api.tasks = [row]
        let screen = TaskScreenModel(store:TaskStore(service:TaskService(client:api)),bulkService:TaskService(client:api),archiveService:TaskArchiveService(client:api))
        await screen.store.refreshList(); let task = try XCTUnwrap(screen.store.list.value?.first), bulk = try XCTUnwrap(screen.bulk)
        bulk.setSelected("7",selected:true,owner:bulk.viewOwner)
        XCTAssertTrue(screen.beginSelectedArchive()); XCTAssertTrue(screen.busy); XCTAssertFalse(screen.beginDelete(task))
        let actions = try XCTUnwrap(screen.archiveActions), id = try XCTUnwrap(actions.context).id
        api.writeReply = .init(status:202,body:Data(#"{"items":[{"id":"7","ok":false,"queued":false}]}"#.utf8))
        _ = await actions.submit(contextID:id); XCTAssertTrue(bulk.selectedIDs.isEmpty)
        actions.close(contextID:id); XCTAssertFalse(screen.busy); XCTAssertTrue(screen.beginArchive(task))
        screen.stop(); XCTAssertNil(actions.context); XCTAssertFalse(screen.busy)
    }

}
