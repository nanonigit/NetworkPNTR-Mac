import XCTest
import ArtexCore
@testable import ArtexMac

@MainActor private final class ArchiveScreenAPI: BackendJSONTransport {
    var calls = 0
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1; return .init(status:503,body:Data())
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
}
