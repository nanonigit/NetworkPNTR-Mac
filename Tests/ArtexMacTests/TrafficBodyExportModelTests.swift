import Foundation
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class BlobSaveChooser: EvidenceDestinationChoosing {
    var url: URL?
    var cancels = 0
    func choose(suggestedFilename: String) async -> URL? { url }
    func cancel() { cancels += 1 }
}
@MainActor private final class BlobSaveFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-body-model-"+UUID().uuidString)
    let bytes = Data([0,255,1,2,3])
    var current = true, available = true, calls = 0, wrongID = false
    var heldMetadata: CheckedContinuation<Void, Never>?
    var holdMetadata = false
    var onAvailability: (() -> Void)?
    var heldReceipt: CheckedContinuation<Void, Never>?
    var holdReceipt = false
    var wrongReceipt = false
    init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func model() -> TrafficBodyExportModel {
        let scope = TrafficBodyExportScope(presentation: UUID(), storeOwner: UUID(), detailRevision: UUID(), trafficID: "\u{FEFF}e\u{301}")
        return TrafficBodyExportModel(scope: scope, isCurrent: { _,_ in self.current }, available: { self.onAvailability?(); return self.available }, metadata: { id, side in
            if self.holdMetadata { await withCheckedContinuation { self.heldMetadata = $0 } }
            return try TrafficBlobDownload(trafficID: self.wrongID ? "other" : id, side: side, expectedSize: 5, expectedSHA256: ArtifactIntegrity.sha256(self.bytes))
        }, exporter: { manifest, destination in
            self.calls += 1
            let bytes = self.wrongReceipt ? Data([9,8,7,6,5]) : self.bytes
            let stagedManifest = try TrafficBlobDownload(trafficID: manifest.trafficID, side: manifest.side, expectedSize: 5, expectedSHA256: ArtifactIntegrity.sha256(bytes))
            let writer = try EvidenceExportWriter(destination: destination, request: stagedManifest)
            try writer.append(bytes)
            let result = BackendDownloadResult(status: 200, byteCount: 5, sha256: ArtifactIntegrity.sha256(bytes))
            let receipt = EvidenceExportReceipt(response: .init(result: result, file: try writer.finish(response: result)))
            if self.holdReceipt { await withCheckedContinuation { self.heldReceipt = $0 } }
            return receipt
        })
    }
}
@MainActor final class TrafficBodyExportModelTests: XCTestCase {
    private func wait(_ check: () -> Bool) async throws {
        for _ in 0..<2000 { if check() { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Model did not settle"); throw CancellationError()
    }
    func testSuccessfulSaveIsVerifiedAndDuplicateDispatchRejected() async throws {
        let f = try BlobSaveFixture(); defer { f.clean() }; let model = f.model(), chooser = BlobSaveChooser()
        chooser.url = f.directory.appendingPathComponent("saved.bin")
        XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser))
        XCTAssertFalse(model.start(.request, owner: model.id, chooser: chooser))
        try await wait { !model.isExporting }
        XCTAssertEqual(f.calls, 1); XCTAssertEqual(try Data(contentsOf: chooser.url!), f.bytes)
        XCTAssertEqual(model.saved?.byteCount, 5); XCTAssertNil(model.failure)
    }
    func testLateMetadataCannotDispatchAfterScopeLossCancelOrStop() async throws {
        for mode in 0..<3 {
            let f = try BlobSaveFixture(); defer { f.clean() }; f.holdMetadata = true
            let model = f.model(), chooser = BlobSaveChooser(); chooser.url = f.directory.appendingPathComponent("never.bin")
            XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser)); try await wait { f.heldMetadata != nil }
            if mode == 0 { f.current = false } else if mode == 1 { model.cancel() } else { model.stop() }
            f.heldMetadata?.resume(); f.heldMetadata = nil
            try await wait { !model.isExporting }
            XCTAssertEqual(f.calls, 0); XCTAssertNil(model.saved)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
        }
    }
    func testLateReceiptIsDiscardedAfterAvailabilityLossCancelOrStop() async throws {
        for mode in 0..<3 {
            let f = try BlobSaveFixture(); defer { f.clean() }; f.holdReceipt = true
            let model = f.model(), chooser = BlobSaveChooser(); chooser.url = f.directory.appendingPathComponent("never.bin")
            XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser)); try await wait { f.heldReceipt != nil }
            if mode == 0 { f.available = false } else if mode == 1 { model.cancel() } else { model.stop() }
            f.heldReceipt?.resume(); f.heldReceipt = nil; try await wait { !model.isExporting }
            XCTAssertNil(model.saved); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
        }
    }
    func testReentrantAdmissionCannotStartTwoExportsOrClaimStoppedOwner() async throws {
        let f = try BlobSaveFixture(); defer { f.onAvailability = nil; f.clean() }
        let model = f.model(), chooser = BlobSaveChooser(); chooser.url = f.directory.appendingPathComponent("one.bin")
        var nested: Bool?
        f.onAvailability = { f.onAvailability = nil; nested = model.start(.response, owner: model.id, chooser: chooser) }
        XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser))
        XCTAssertEqual(nested, false)
        try await wait { !model.isExporting }
        XCTAssertEqual(f.calls, 1)
        let stopped = f.model(); f.onAvailability = { f.onAvailability = nil; stopped.stop() }
        XCTAssertFalse(stopped.start(.response, owner: stopped.id, chooser: chooser))
    }
    func testOtherwiseValidReceiptForDifferentBodyCannotPublish() async throws {
        let f = try BlobSaveFixture(); defer { f.clean() }; f.wrongReceipt = true
        let model = f.model(), chooser = BlobSaveChooser(); chooser.url = f.directory.appendingPathComponent("never.bin")
        XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser)); try await wait { !model.isExporting }
        XCTAssertNotNil(model.failure); XCTAssertNil(model.saved)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
    }
    func testWrongIdentityUnsupportedOwnerAndPanelCancelNeverPublish() async throws {
        let f = try BlobSaveFixture(); defer { f.clean() }; let model = f.model(), chooser = BlobSaveChooser()
        XCTAssertFalse(model.start(.request, owner: UUID(), chooser: chooser))
        f.available = false; XCTAssertFalse(model.start(.request, owner: model.id, chooser: chooser))
        f.available = true; XCTAssertTrue(model.start(.request, owner: model.id, chooser: chooser)); try await wait { !model.isExporting }
        XCTAssertEqual(f.calls, 0); XCTAssertNil(model.failure)
        f.wrongID = true; chooser.url = f.directory.appendingPathComponent("never.bin")
        XCTAssertTrue(model.start(.response, owner: model.id, chooser: chooser)); try await wait { !model.isExporting }
        XCTAssertNotNil(model.failure); XCTAssertEqual(f.calls, 0)
        model.stop(); XCTAssertFalse(model.start(.response, owner: model.id, chooser: chooser))
    }
}
