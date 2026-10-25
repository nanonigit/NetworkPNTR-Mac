import Foundation
import XCTest
@testable import ArtexCore

@MainActor private final class StagingExerciseAPI: BackendJSONTransport, TaskStagingUploading {
    enum Fault { case none, wrongName, foreignDraft, wrongSize, empty, wrongBytes, badStatus, clobber, cancelUpload, cancelRead }
    var fault = Fault.none
    var uploads = 0
    var reads = 0
    var paths: [String] = []
    var saved: [String:Data] = [:]
    func uploadTaskStaging(draftID: UUID, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [TaskStagedAttachment] {
        uploads += 1
        if fault == .cancelUpload { withUnsafeCurrentTask { $0?.cancel() } }
        if fault == .empty { return [] }
        let names = uploads == 1 ? TaskStagingExercise.firstNames : TaskStagingExercise.repeatNames
        var result: [TaskStagedAttachment] = []
        for index in names.indices {
            let name = fault == .wrongName && index == 0 ? "other.bin" : names[index]
            let draft = fault == .foreignDraft ? UUID() : draftID
            let size = TaskStagingExercise.contents[index].count + (fault == .wrongSize ? 1 : 0)
            let relative = "uploads/" + name
            saved["drafts/"+draft.uuidString.lowercased()+"/"+relative] = TaskStagingExercise.contents[index]
            let json = try JSONSerialization.data(withJSONObject:["name":name,"path":relative,"size":size,"abs":"/state/app/data/drafts/"+draft.uuidString.lowercased()+"/"+relative])
            let decoder = JSONDecoder(); decoder.userInfo[TaskStagedAttachment.draftKey] = draft
            result.append(try decoder.decode(TaskStagedAttachment.self,from:json))
        }
        if fault == .clobber && uploads == 2 { saved["drafts/"+draftID.uuidString.lowercased()+"/uploads/fixture.bin"] = Data("clobbered".utf8) }
        return result
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        reads += 1; paths.append(path)
        XCTAssertEqual(method,"GET"); XCTAssertNil(body); XCTAssertNil(bearer)
        XCTAssertTrue(path.hasPrefix("/api/workspace/download?"))
        if fault == .cancelRead { withUnsafeCurrentTask { $0?.cancel() } }
        let query = URLComponents(string:"http://localhost"+path)?.queryItems?.first(where:{$0.name == "path"})?.value ?? ""
        guard let bytes = saved[query] else { throw BackendAPIError.invalidResponse }
        return .init(status:fault == .badStatus ? 503 : 200,body:fault == .wrongBytes ? Data("wrong".utf8) : bytes)
    }
}

final class TaskStagingExerciseTests: XCTestCase {
    private let draft = UUID(uuidString:"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private var files: [URL] {
        ["/owned/fixture.bin","/owned/empty.txt","/owned/second/fixture.bin","/owned/日本-é.txt"].map { URL(fileURLWithPath:$0) }
    }
    @MainActor func testTwoBatchesReadBackExactContentAndPreserveOriginals() async throws {
        let api = StagingExerciseAPI()
        let result = try await TaskStagingExercise.run(files:files,draftID:draft,client:api,uploader:api)
        XCTAssertEqual(api.uploads,2); XCTAssertEqual(api.reads,12)
        XCTAssertEqual(result.records.map(\.name),TaskStagingExercise.firstNames+TaskStagingExercise.repeatNames)
        XCTAssertEqual(result.records.map(\.size),[70001,0,28,1280,70001,0,28,1280])
        XCTAssertTrue(result.originalFilesPreserved)
        XCTAssertTrue(result.englishManifest.contains("<draft>/uploads/fixture-3.bin"))
        XCTAssertTrue(result.japaneseManifest.contains("【アップロードファイル(絶対パス)】"))
        XCTAssertFalse(result.englishManifest.contains(draft.uuidString.lowercased()))
        let json = String(decoding:try JSONEncoder().encode(result),as:UTF8.self)
        XCTAssertFalse(json.contains("/owned/")); XCTAssertFalse(json.contains("/state/"))
        XCTAssertTrue(result.records.allSatisfy { $0.sha256.count == 64 })
    }
    @MainActor func testMalformedMetadataAndWrongContentCannotYieldVerifiedReport() async throws {
        for fault in [StagingExerciseAPI.Fault.wrongName,.foreignDraft,.wrongSize,.empty,.wrongBytes,.badStatus,.clobber] {
            let api = StagingExerciseAPI(); api.fault = fault
            do { _ = try await TaskStagingExercise.run(files:files,draftID:draft,client:api,uploader:api); XCTFail("Invalid exercise accepted") }
            catch { XCTAssertFalse(error.localizedDescription.contains("/state/")) }
            XCTAssertLessThanOrEqual(api.uploads,2)
        }
    }
    @MainActor func testCancellationBeforeAndAfterDispatchNeverRetries() async throws {
        for fault in [StagingExerciseAPI.Fault.none,.cancelUpload,.cancelRead] {
            let api = StagingExerciseAPI(); api.fault = fault
            let pending = Task { @MainActor in try await TaskStagingExercise.run(files:self.files,draftID:self.draft,client:api,uploader:api) }
            if fault == .none { pending.cancel() }
            do { _ = try await pending.value; XCTFail("Cancellation accepted") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertLessThanOrEqual(api.uploads,1)
        }
    }
    @MainActor func testInvalidFixtureSelectionNeverDispatches() async throws {
        let api = StagingExerciseAPI()
        for selected in [[],Array(files.reversed()),[URL(string:"https://example.invalid/fixture.bin")!]+Array(files.dropFirst())] {
            do { _ = try await TaskStagingExercise.run(files:selected,draftID:draft,client:api,uploader:api); XCTFail("Invalid selection") } catch { }
        }
        XCTAssertEqual(api.uploads,0); XCTAssertEqual(api.reads,0)
    }
}
