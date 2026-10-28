import Darwin
import Foundation
import XCTest
@testable import ArtexCore

final class EvidenceCancellationProbeTests: XCTestCase {
    private func manifest(binding: String = "7") throws -> FindingEvidenceDownload {
        try FindingEvidenceDownload(findingID: "1", bindingID: binding, side: .response, expectedSize: 135266321, expectedSHA256: String(repeating: "a", count: 64))
    }
    private func socket() throws -> (BackendUploadSocket, Int32) {
        var pair: [Int32] = [0,0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw POSIXError(.EIO) }
        return (BackendUploadSocket(owning: pair[0]), pair[1])
    }
    func testCompletedWorkerPendingAcceptanceCannotCountAsInterruptedStream() throws {
        let request = try manifest(), probe = EvidenceCancellationProbe(expected: request)
        let (transfer, peer) = try socket(); defer { Darwin.close(peer) }
        transfer.finish()
        probe.record(operationID: UUID(), manifest: request, interrupted: transfer.cancel())
        XCTAssertNil(probe.interruptedOperationID)
        XCTAssertThrowsError(try transfer.validateCompletion())
    }
    func testExactlyOneMatchingOpenSocketInterruptionIsRequired() throws {
        let request = try manifest(), probe = EvidenceCancellationProbe(expected: request), id = UUID()
        let (transfer, peer) = try socket(); defer { transfer.finish(); Darwin.close(peer) }
        XCTAssertNil(probe.interruptedOperationID)
        probe.record(operationID: id, manifest: request, interrupted: transfer.cancel())
        XCTAssertEqual(probe.interruptedOperationID, id)
        probe.record(operationID: id, manifest: request, interrupted: false)
        XCTAssertNil(probe.interruptedOperationID)
        let foreign = EvidenceCancellationProbe(expected: request)
        foreign.record(operationID: UUID(), manifest: try manifest(binding: "8"), interrupted: true)
        XCTAssertNil(foreign.interruptedOperationID)
    }
}
