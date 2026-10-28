import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import ArtexCore

final class EvidenceExportTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artex-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private func spec(_ data: Data, hash: String? = nil) throws -> FindingEvidenceDownload {
        try .init(findingID: "9101", bindingID: "7", side: .response, expectedSize: Int64(data.count), expectedSHA256: hash ?? ArtifactIntegrity.sha256(data), contextTaskID: "8101")
    }
    private func verified(_ data: Data, destination: EvidenceExportDestination) throws -> VerifiedEvidenceFile {
        let request = try spec(data), writer = try EvidenceExportWriter(destination: destination, request: request)
        for start in stride(from: 0, to: data.count, by: 65536) { try writer.append(data.subdata(in: start..<min(start + 65536, data.count))) }
        return try writer.finish(response: .init(status: 200, byteCount: Int64(data.count), sha256: request.expectedSHA256))
    }
    func testOnlyFixedEvidenceRouteAndValidManifestProduceAuthenticatedRequest() throws {
        let request = try spec(Data([0, 255, 1]))
        let text = String(decoding: try request.request(bearer: "fixture.jwt"), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("GET /api/exploration/findings/9101/traffic/7/body?side=response&download=1&context_task=8101 HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("Accept: application/octet-stream\r\n")); XCTAssertTrue(text.contains("Accept-Encoding: identity\r\n"))
        XCTAssertEqual(request.suggestedFilename, "evidence-7-response.bin")
        for id in ["0", "-1", "1/other", "1\r\nInjected"] {
            XCTAssertThrowsError(try FindingEvidenceDownload(findingID: id, bindingID: "7", side: .request, expectedSize: 0, expectedSHA256: String(repeating: "a", count: 64)))
        }
        for hash in ["", String(repeating: "A", count: 64), String(repeating: "a", count: 63), String(repeating: "g", count: 64)] { XCTAssertThrowsError(try spec(Data(), hash: hash)) }
        for token in ["", "bad token", "bad\r\n"] { XCTAssertThrowsError(try request.request(bearer: token)) }
        XCTAssertThrowsError(try FindingEvidenceDownload(findingID: "1", bindingID: "7", side: .response, expectedSize: -1, expectedSHA256: String(repeating: "a", count: 64)))
    }
    func testActualFullBinaryFileBeyondJSONLimitMatchesOriginalBytesAndPrivateModes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("literal 日本語.bin"), data = Data((0..<(5 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0) })
        let destination = try EvidenceExportDestination(newFileURL: url), request = try spec(data)
        let writer = try EvidenceExportWriter(destination: destination, request: request)
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: stage.path)[.posixPermissions] as? Int, 0o700)
        let decoder = try BackendDownloadDigest(expectedSize: Int64(data.count), maximumBytes: Int64(data.count), onBody: { try writer.append($0) })
        try decoder.consume(Data("HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\n\r\n".utf8))
        for start in stride(from: 0, to: data.count, by: 65536) { try decoder.consume(data.subdata(in: start..<min(start + 65536, data.count))) }
        let file = try writer.finish(response: decoder.finish())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let saved = try file.commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), data); XCTAssertEqual(saved.byteCount, Int64(data.count)); XCTAssertEqual(saved.sha256, request.expectedSHA256)
        XCTAssertTrue(saved.stagingCleanupComplete)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: saved.url.path)[.posixPermissions] as? Int, 0o600)
        try file.discard(); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
    func testEmptyBodyAndDiskHashVerificationRejectForgedNetworkDigest() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let empty = try verified(Data(), destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("empty.bin")))
        XCTAssertEqual(try empty.commit().byteCount, 0)
        let expected = Data([1, 2, 3]), request = try spec(expected)
        let writer = try EvidenceExportWriter(destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("bad.bin")), request: request)
        try writer.append(Data([4, 5, 6]))
        XCTAssertThrowsError(try writer.finish(response: .init(status: 200, byteCount: 3, sha256: request.expectedSHA256)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["empty.bin"])
    }
    func testWrongLengthHashOversizedChunkAndDiscardRemoveAllPartialState() throws {
        for mode in 0..<4 {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let request = try spec(Data([1, 2, 3]))
            let writer = try EvidenceExportWriter(destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), request: request)
            if mode == 0 { XCTAssertThrowsError(try writer.append(Data([1, 2, 3, 4]))) }
            else if mode == 1 { XCTAssertThrowsError(try writer.append(Data(repeating: 1, count: 65537))) }
            else if mode == 2 {
                try writer.append(Data([1])); XCTAssertThrowsError(try writer.finish(response: .init(status: 200, byteCount: 1, sha256: request.expectedSHA256)))
            } else {
                try writer.append(Data([1, 2, 3])); XCTAssertThrowsError(try writer.finish(response: .init(status: 200, byteCount: 3, sha256: String(repeating: "a", count: 64))))
            }
            try writer.discard(); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    func testExistingTargetAndRacingSymlinkAreNeverReplaced() throws {
        for link in [false, true] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("output.bin"), sentinel = Data("keep original".utf8)
            let destination = try EvidenceExportDestination(newFileURL: url), file = try verified(Data([0, 255]), destination: destination)
            if link {
                let victim = root.appendingPathComponent("victim.bin"); try sentinel.write(to: victim)
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: victim)
            } else { try sentinel.write(to: url) }
            XCTAssertThrowsError(try file.commit()); XCTAssertEqual(try Data(contentsOf: url), sentinel)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".artex-evidence-") })
        }
    }
    func testNonFileAndSymlinkParentDestinationsAreRejected() throws {
        XCTAssertThrowsError(try EvidenceExportDestination(newFileURL: XCTUnwrap(URL(string: "https://outside.invalid/file"))))
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("actual"), link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        XCTAssertThrowsError(try EvidenceExportDestination(newFileURL: link.appendingPathComponent("output.bin")))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: actual.path).isEmpty)
    }
    func testPinnedParentCannotBeRedirectedByDirectoryReplacement() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen"), moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        let file = try verified(Data([0, 255]), destination: EvidenceExportDestination(newFileURL: chosen.appendingPathComponent("output.bin")))
        try FileManager.default.moveItem(at: chosen, to: moved)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        let saved = try file.commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), Data([0, 255]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: chosen.appendingPathComponent("output.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("output.bin").path))
    }
    func testCancelledPublishDiscardsVerifiedPartialWithoutCreatingFinalName() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("output.bin"), file = try verified(Data([0, 255]), destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try file.commit(); XCTFail("Cancelled export published") } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

extension EvidenceExportTests {
    func testMovedStagingDirectoryCannotBeReportedAsCompleteCleanup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = try EvidenceExportWriter(destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), request: spec(Data([1])))
        try writer.append(Data([1]))
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let moved = root.appendingPathComponent("moved-stage")
        try FileManager.default.moveItem(at: stage, to: moved)
        XCTAssertThrowsError(try writer.discard())
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }
    func testReplacementStagingDirectoryIsNeverDeletedAndPublishedReceiptReportsCleanupIncomplete() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try verified(Data([0, 255]), destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")))
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let moved = root.appendingPathComponent("moved-stage")
        try FileManager.default.moveItem(at: stage, to: moved)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let saved = try file.commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), Data([0, 255]))
        XCTAssertFalse(saved.stagingCleanupComplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }
}

extension EvidenceExportTests {
    func testReplacementPartialFileIsNotDeletedByCleanup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = try EvidenceExportWriter(destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), request: spec(Data([1])))
        try writer.append(Data([1]))
        let stage = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let body = stage.appendingPathComponent("body.partial"), moved = stage.appendingPathComponent("owned-moved")
        try FileManager.default.moveItem(at: body, to: moved)
        let unrelated = Data("unrelated".utf8); try unrelated.write(to: body)
        XCTAssertThrowsError(try writer.discard())
        XCTAssertTrue(FileManager.default.fileExists(atPath: body.path))
        if FileManager.default.fileExists(atPath: body.path) { XCTAssertEqual(try Data(contentsOf: body), unrelated) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }
}
