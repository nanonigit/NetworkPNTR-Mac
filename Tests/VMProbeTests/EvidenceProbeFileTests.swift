import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import ArtexCore
@testable import VMProbe

final class EvidenceProbeFileTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-evidence-probe-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    func testIndependentFullFileHashAcceptsLiteralAndEmptyAndRejectsCorruption() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let literal = Data("\u{FEFF}e\u{0301} English Japanese 日本語 中文 한국어\r\n".utf8)
        for (name, bytes) in [("literal", literal), ("empty", Data())] {
            let url = root.appendingPathComponent(name); try bytes.write(to: url)
            let expected = try XCTUnwrap(EvidenceFixtureClient.expectedBodies[name])
            let proof = try EvidenceProbeFile.verify(url, body: name, expected: expected)
            XCTAssertEqual(proof.body, name); XCTAssertEqual(proof.byteCount, Int64(bytes.count)); XCTAssertEqual(proof.sha256, expected.sha256)
            try Data(repeating: 120, count: max(1, bytes.count)).write(to: url)
            XCTAssertThrowsError(try EvidenceProbeFile.verify(url, body: name, expected: expected))
        }
    }
    func testRealBinaryFileIsStreamedWithoutAWholeFileDataRead() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("binary")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url)
        let chunk = Data((0..<65536).map { UInt8(truncatingIfNeeded: $0) })
        var remaining = try XCTUnwrap(EvidenceFixtureClient.expectedBodies["binary"]).size
        while remaining > 0 {
            let bytes = chunk.prefix(Int(min(remaining, 65536))); try file.write(contentsOf: bytes); remaining -= Int64(bytes.count)
        }
        try file.close()
        let expected = try XCTUnwrap(EvidenceFixtureClient.expectedBodies["binary"])
        XCTAssertEqual(try EvidenceProbeFile.verify(url, body: "binary", expected: expected).sha256, expected.sha256)
    }
    func testSymlinkDirectoryMissingAndFIFOAreRejectedBeforeBlocking() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target"), link = root.appendingPathComponent("link"), fifo = root.appendingPathComponent("fifo")
        try Data().write(to: target); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let expected = try XCTUnwrap(EvidenceFixtureClient.expectedBodies["empty"])
        for url in [link, root, fifo, root.appendingPathComponent("missing")] {
            XCTAssertThrowsError(try EvidenceProbeFile.verify(url, body: "empty", expected: expected))
        }
    }
}
