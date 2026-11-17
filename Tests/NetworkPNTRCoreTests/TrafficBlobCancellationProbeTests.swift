import Darwin
import Foundation
import XCTest
@testable import NetworkPNTRCore

final class TrafficBlobCancellationProbeTests: XCTestCase, @unchecked Sendable {
    private func manifest(id: String = "\u{FEFF}e\u{301}", side: FindingEvidenceSide = .response, size: Int64 = 262401, hash: String = String(repeating: "a", count: 64)) throws -> TrafficBlobDownload {
        try .init(trafficID: id, side: side, expectedSize: size, expectedSHA256: hash)
    }
    private func socket() throws -> (BackendUploadSocket, Int32) {
        var pair: [Int32] = [0,0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw POSIXError(.EIO) }
        return (BackendUploadSocket(owning: pair[0]), pair[1])
    }
    private func waitForPartial(_ probe: TrafficBlobCancellationProbe) async throws -> TrafficBlobCancellationProbe.Partial {
        for _ in 0..<1000 {
            if let partial = probe.partial { return partial }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RuntimeError.timeout("blob probe unit partial")
    }
    func testOneMatchingPartialOpenSocketCancellationProducesWitness() async throws {
        let expected = try manifest(), probe = TrafficBlobCancellationProbe(expected: expected), id = UUID()
        let (transfer, peer) = try socket(); defer { transfer.finish(); Darwin.close(peer) }
        let worker = Task.detached { try probe.pauseAfterAppend(operationID: id, manifest: expected, bytes: 65536) }
        let partial = try await waitForPartial(probe)
        XCTAssertEqual(partial.operationID, id); XCTAssertEqual(partial.bytes, 65536)
        XCTAssertNil(probe.witness)
        probe.recordCancellation(operationID: id, manifest: expected, interrupted: transfer.cancel())
        do { try await worker.value; XCTFail("Interrupted reader must fail") } catch is CancellationError { }
        XCTAssertEqual(probe.witness?.operationID, id); XCTAssertEqual(probe.witness?.bytes, 65536)
        probe.recordCancellation(operationID: id, manifest: expected, interrupted: false)
        XCTAssertNil(probe.witness)
    }
    func testWrongLiteralIDSideSizeHashAndNonpartialBytesCannotPause() throws {
        let expected = try manifest()
        for wrong in [try manifest(id: "\u{FEFF}é"), try manifest(side: .request), try manifest(size: 262402), try manifest(hash: String(repeating: "b", count: 64))] {
            let probe = TrafficBlobCancellationProbe(expected: expected)
            XCTAssertThrowsError(try probe.pauseAfterAppend(operationID: UUID(), manifest: wrong, bytes: 1))
            XCTAssertNil(probe.partial); XCTAssertNil(probe.witness)
        }
        for bytes in [Int64(-1),0,262401,262402] {
            let probe = TrafficBlobCancellationProbe(expected: expected)
            XCTAssertThrowsError(try probe.pauseAfterAppend(operationID: UUID(), manifest: expected, bytes: bytes))
            XCTAssertNil(probe.partial); XCTAssertNil(probe.witness)
        }
    }
    func testCancellationBeforeBodyOrAfterSocketCompletionIsNotProof() async throws {
        let expected = try manifest(), early = TrafficBlobCancellationProbe(expected: expected), id = UUID()
        early.recordCancellation(operationID: id, manifest: expected, interrupted: true)
        XCTAssertThrowsError(try early.pauseAfterAppend(operationID: id, manifest: expected, bytes: 1))
        XCTAssertNil(early.witness)
        let late = TrafficBlobCancellationProbe(expected: expected)
        let (transfer, peer) = try socket(); defer { Darwin.close(peer) }
        let worker = Task.detached { try late.pauseAfterAppend(operationID: id, manifest: expected, bytes: 1) }
        _ = try await waitForPartial(late); transfer.finish()
        late.recordCancellation(operationID: id, manifest: expected, interrupted: transfer.cancel())
        do { try await worker.value; XCTFail("Finished socket is not an interruption") } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertNil(late.witness)
    }
    func testWrongOperationAndWrongManifestInvalidatePausedProof() async throws {
        for wrongOperation in [false,true] {
            let expected = try manifest(), probe = TrafficBlobCancellationProbe(expected: expected), id = UUID()
            let wrong = try manifest(id: "other")
            let worker = Task.detached { try probe.pauseAfterAppend(operationID: id, manifest: expected, bytes: 1) }
            _ = try await waitForPartial(probe)
            probe.recordCancellation(operationID: wrongOperation ? UUID() : id, manifest: wrongOperation ? expected : wrong, interrupted: true)
            do { try await worker.value; XCTFail("Foreign cancellation") } catch { XCTAssertFalse(error is CancellationError) }
            XCTAssertNil(probe.witness)
        }
    }
    func testTimeoutInvalidatesProofAndReleasesReader() async throws {
        let expected = try manifest(), probe = TrafficBlobCancellationProbe(expected: expected, timeout: 0.01), id = UUID()
        do { try await Task.detached { try probe.pauseAfterAppend(operationID: id, manifest: expected, bytes: 1) }.value; XCTFail("Timed out") }
        catch { XCTAssertFalse(error is CancellationError) }
        probe.recordCancellation(operationID: id, manifest: expected, interrupted: true)
        XCTAssertNil(probe.witness)
    }
    func testRealStagingAppendPausesOwnedWorkerAndCancellationRemovesPartialFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-blob-interrupt-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try manifest(), probe = TrafficBlobCancellationProbe(expected: expected), id = UUID()
        let (transfer, peer) = try socket(); defer { transfer.finish(); Darwin.close(peer) }
        let wire = Data("HTTP/1.1 200 OK\r\nContent-Length: 262401\r\n\r\n".utf8) + Data(repeating: 7, count: 4096)
        XCTAssertEqual(wire.withUnsafeBytes { Darwin.write(peer, $0.baseAddress, $0.count) }, wire.count)
        let destination = try EvidenceExportDestination(newFileURL: directory.appendingPathComponent("never.bin"))
        let context = TrafficBlobCancellationProbe.Transfer(probe: probe, operationID: id, manifest: expected)
        let worker = Task.detached {
            try TrafficBlobCancellationProbe.$current.withValue(context) {
                try EvidenceDownloadStaging.exchange(socket: transfer, preamble: Data(), request: Data("GET /fixture HTTP/1.1\r\n\r\n".utf8), manifest: expected, destination: destination, timeout: .seconds(2))
            }
        }
        var partial: TrafficBlobCancellationProbe.Partial?
        for _ in 0..<200 {
            if let value = probe.partial { partial = value; break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let observed = try EvidenceProbeTestFiles.partialLength(directory)
        probe.recordCancellation(operationID: id, manifest: expected, interrupted: transfer.cancel())
        do { _ = try await worker.value; XCTFail("Canceled worker returned a receipt") } catch is CancellationError { }
        XCTAssertEqual(partial?.operationID, id)
        XCTAssertEqual(partial?.bytes, 4096)
        XCTAssertEqual(observed, 4096)
        XCTAssertEqual(probe.witness?.operationID, id)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    @MainActor func testLateRecorderCannotBeatReaderTimeoutCheck() async throws {
        let expected = try manifest(), start = ContinuousClock.now, id = UUID()
        // The reader observed time before waiting; the recorder observes expiry before the reader resumes.
        let probe = TrafficBlobCancellationProbe(expected: expected, now: {
            Thread.isMainThread ? start.advanced(by: .seconds(11)) : start
        })
        let worker = Task.detached { try probe.pauseAfterAppend(operationID: id, manifest: expected, bytes: 1) }
        _ = try await waitForPartial(probe)
        probe.recordCancellation(operationID: id, manifest: expected, interrupted: true)
        do { try await worker.value; XCTFail("Late recorder") } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertNil(probe.witness)
    }
    func testTaskLocalScopeIsExplicitAndDoesNotLeak() async throws {
        let expected = try manifest(), probe = TrafficBlobCancellationProbe(expected: expected), id = UUID()
        XCTAssertNil(TrafficBlobCancellationProbe.current)
        let context = TrafficBlobCancellationProbe.Transfer(probe: probe, operationID: id, manifest: expected)
        await TrafficBlobCancellationProbe.$current.withValue(context) {
            XCTAssertEqual(TrafficBlobCancellationProbe.current?.operationID, id)
            let detachedIsEmpty = await Task.detached { TrafficBlobCancellationProbe.current == nil }.value
            XCTAssertTrue(detachedIsEmpty)
        }
        XCTAssertNil(TrafficBlobCancellationProbe.current)
    }
}

private enum EvidenceProbeTestFiles {
    static func partialLength(_ root: URL) throws -> Int64? {
        let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".artex-evidence-") }
        guard let stage = stages.first else { return nil }
        return (try FileManager.default.attributesOfItem(atPath: stage.appendingPathComponent("body.partial").path)[.size] as? NSNumber)?.int64Value
    }
}
