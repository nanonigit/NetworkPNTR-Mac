import CryptoKit
import Foundation
import XCTest
@testable import NetworkPNTRCore

final class BackendDownloadDigestTests: XCTestCase {
    private func header(_ length: Int64, extra: String = "", status: Int = 200) -> Data {
        Data("HTTP/1.1 \(status) Fixture\r\nContent-Length: \(length)\r\n\(extra)\r\n".utf8)
    }
    func testSplitHeaderAndBinaryChunksHashAllBytesWithoutRetainingBody() throws {
        let bytes = Data((0..<200003).map { UInt8($0 % 256) })
        let decoder = try BackendDownloadDigest(expectedSize: Int64(bytes.count))
        let fields = header(Int64(bytes.count))
        for byte in fields { try decoder.consume(Data([byte])) }
        for offset in stride(from: 0, to: bytes.count, by: 617) {
            try decoder.consume(Data(bytes[offset..<min(bytes.count, offset + 617)]))
            XCTAssertLessThanOrEqual(decoder.bufferedBytes, 65536)
        }
        let result = try decoder.finish()
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.byteCount, Int64(bytes.count))
        XCTAssertEqual(result.sha256, ArtifactIntegrity.sha256(bytes))
        XCTAssertEqual(decoder.bufferedBytes, 0)
        XCTAssertThrowsError(try decoder.consume(Data([0])))
        XCTAssertThrowsError(try decoder.finish())
    }
    func testEmptyAndActual128MiBIncrementalBoundary() throws {
        let empty = try BackendDownloadDigest(expectedSize: 0)
        try empty.consume(header(0))
        XCTAssertEqual(try empty.finish().sha256, ArtifactIntegrity.sha256(Data()))
        let size: Int64 = 128 * 1024 * 1024
        let decoder = try BackendDownloadDigest(expectedSize: size)
        try decoder.consume(header(size))
        let chunk = Data(repeating: 0xA7, count: 65536)
        var independent = SHA256()
        for _ in 0..<2048 { try decoder.consume(chunk); independent.update(data: chunk) }
        let result = try decoder.finish()
        XCTAssertEqual(result.byteCount, size)
        XCTAssertEqual(result.sha256, independent.finalize().map { String(format: "%02x", $0) }.joined())
        XCTAssertThrowsError(try BackendDownloadDigest(expectedSize: size + 1))
        XCTAssertThrowsError(try BackendDownloadDigest(expectedSize: -1))
    }
    func testMalformedAmbiguousEncodedOrUnexpectedSuccessIsRejectedAndTerminal() throws {
        let invalid = [
            "HTTP/1.1 200 OK\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Encoding: gzip\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: +1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 99999999999999999999999\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n",
            "HTTP/1.1 206 Partial\r\nContent-Length: 1\r\n\r\n",
            "HTTP/1.1 200 OK\r\n Content-Length: 1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nBad Header: x\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nX: bad\nvalue\r\n\r\n"
        ]
        for text in invalid {
            let decoder = try BackendDownloadDigest(expectedSize: 1)
            XCTAssertThrowsError(try decoder.consume(Data(text.utf8)), text)
            XCTAssertThrowsError(try decoder.finish(), text)
            XCTAssertThrowsError(try decoder.consume(Data([0])), text)
        }
    }
    func testTruncationExtraBytesAndHeaderFeedBoundsFail() throws {
        let short = try BackendDownloadDigest(expectedSize: 2)
        try short.consume(header(2) + Data([1]))
        XCTAssertThrowsError(try short.finish())
        XCTAssertThrowsError(try short.consume(Data([2])))
        let extra = try BackendDownloadDigest(expectedSize: 1)
        XCTAssertThrowsError(try extra.consume(header(1) + Data([1,2])))
        let largeFeed = try BackendDownloadDigest(expectedSize: 0)
        XCTAssertThrowsError(try largeFeed.consume(Data(repeating: 65, count: 65537)))
        let largeHeader = try BackendDownloadDigest(expectedSize: 0)
        try largeHeader.consume(Data(repeating: 65, count: 65536))
        XCTAssertThrowsError(try largeHeader.consume(Data([65])))
    }
    func testUnauthorizedAndCloseDelimitedErrorsRemainBounded() throws {
        let unauthorized = try BackendDownloadDigest(expectedSize: 8000000)
        try unauthorized.consume(header(2, status: 401) + Data("{}".utf8))
        XCTAssertTrue(unauthorized.isComplete)
        XCTAssertEqual(try unauthorized.finish().status, 401)
        let closed = try BackendDownloadDigest(expectedSize: 0)
        try closed.consume(Data("HTTP/1.1 404 Missing\r\nConnection: close\r\n\r\nmissing".utf8))
        XCTAssertFalse(closed.isComplete)
        XCTAssertEqual(try closed.finish().byteCount, 7)
        let oversized = try BackendDownloadDigest(expectedSize: 0)
        XCTAssertThrowsError(try oversized.consume(header(4 * 1024 * 1024 + 1, status: 500)))
    }
    func testCancellationIsTerminalAndDiscardedBytesCannotProduceDigest() throws {
        let decoder = try BackendDownloadDigest(expectedSize: 2)
        try decoder.consume(header(2) + Data([1]))
        decoder.cancel()
        XCTAssertThrowsError(try decoder.consume(Data([2]))) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(decoder.bufferedBytes, 0)
    }
}
