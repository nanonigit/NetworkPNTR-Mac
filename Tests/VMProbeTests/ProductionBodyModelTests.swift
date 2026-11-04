import ArtexCore
import Foundation
import XCTest

@MainActor private final class ProductionCancelChooser: EvidenceDestinationChoosing {
    func choose(suggestedFilename: String) async -> URL? { nil }
    func cancel() { }
}
@MainActor final class ProductionBodyModelTests: XCTestCase {
    func testProbeUsesSharedProductionModelAndRetirementWithoutAppKit() async throws {
        let scope = TrafficBodyExportScope(presentation: UUID(), storeOwner: UUID(), detailRevision: UUID(), trafficID: "opaque")
        let model = TrafficBodyExportModel(scope: scope, isCurrent: { _,_ in true }, available: { true }, metadata: { id, side in
            try TrafficBlobDownload(trafficID: id, side: side, expectedSize: 0, expectedSHA256: ArtifactIntegrity.sha256(Data()))
        }, exporter: { _,_ in XCTFail("Canceled chooser must not transfer"); throw CancellationError() })
        XCTAssertTrue(model.start(.response, owner: model.id, chooser: ProductionCancelChooser()))
        for _ in 0..<1000 { if !model.isExporting { break }; await Task.yield() }
        XCTAssertFalse(model.isExporting); XCTAssertNil(model.saved); XCTAssertNil(model.failure)
        let retirement = TrafficBodyExportRetirement(); retirement.retain(model)
        XCTAssertFalse(model.isActive); XCTAssertEqual(retirement.pendingCount, 0); XCTAssertTrue(retirement.notices.isEmpty)
    }
}
