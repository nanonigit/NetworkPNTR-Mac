import Darwin
import Foundation
import XCTest
@testable import ArtexCore

final class ChatMultipartBodyTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artex-upload-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func file(_ parent: URL, _ name: String, _ data: Data = Data()) throws -> URL {
        let url = parent.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    private func drain(_ body: ChatMultipartBody, chunk: Int = 65536) throws -> Data {
        var wire = Data()
        while let bytes = try body.read(maximum: chunk) {
            XCTAssertFalse(bytes.isEmpty); XCTAssertLessThanOrEqual(bytes.count, chunk)
            wire.append(bytes)
        }
        return wire
    }
    func testMultipartIncludesOrderedRepeatedFilesEmptyContentAndNoHostPaths() throws {
        let root = try directory(), second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let first = try file(root, "資料.txt", Data([0, 255, 13, 10, 65]))
        let empty = try file(second, "資料.txt")
        let body = try ChatMultipartBody(files: [first, empty], boundary: "fixture-boundary")
        let prelude = "--fixture-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"資料.txt\"\r\nContent-Type: application/octet-stream\r\n\r\n"
        let expected = Data(prelude.utf8) + Data([0, 255, 13, 10, 65]) + Data(("\r\n" + prelude + "\r\n--fixture-boundary--\r\n").utf8)
        XCTAssertEqual(body.contentType, "multipart/form-data; boundary=fixture-boundary")
        XCTAssertEqual(body.contentLength, Int64(expected.count))
        let wire = try drain(body, chunk: 1)
        XCTAssertEqual(wire, expected)
        XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains(root.path))
        XCTAssertNil(try body.read())
    }
    func testFilenamesCannotInjectPartHeaders() throws {
        let url = try file(directory(), "quote\"\r\nname.txt", Data("test".utf8))
        let body = try ChatMultipartBody(files: [url], boundary: "fixture")
        let wire = String(decoding: try drain(body), as: UTF8.self)
        XCTAssertTrue(wire.contains("filename=\"quote%22%0D%0Aname.txt\"\r\n"))
        XCTAssertFalse(wire.contains("filename=\"quote\"\r\n"))
    }
    func testExactBodyLimitIncludesFramingAndRejectsOneByteOverWithoutReadingPayload() throws {
        let url = try file(directory(), "sparse.bin")
        let empty = try ChatMultipartBody(files: [url], boundary: "size-fixture")
        let overhead = empty.contentLength
        empty.close()
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(128 * 1024 * 1024 - overhead))
        let exact = try ChatMultipartBody(files: [url], boundary: "size-fixture")
        XCTAssertEqual(exact.contentLength, 128 * 1024 * 1024)
        exact.close()
        try handle.truncate(atOffset: UInt64(128 * 1024 * 1024 - overhead + 1))
        XCTAssertThrowsError(try ChatMultipartBody(files: [url], boundary: "size-fixture"))
        // Multipart support must not widen the unrelated JSON path.
        XCTAssertThrowsError(try BackendHTTPRequest.make(method: "POST", path: "/api/chat/upload", body: Data(repeating: 0, count: 4 * 1024 * 1024 + 1), bearer: nil))
    }
    func testRejectsInvalidSelectionBoundaryAndNonRegularFilesWithoutBlocking() throws {
        let root = try directory(), url = try file(root, "ok.txt")
        XCTAssertThrowsError(try ChatMultipartBody(files: []))
        XCTAssertThrowsError(try ChatMultipartBody(files: [URL(string: "https://example.com/file")!]))
        XCTAssertThrowsError(try ChatMultipartBody(files: [root]))
        XCTAssertThrowsError(try ChatMultipartBody(files: [root.appendingPathComponent("missing")]))
        for boundary in ["", "line\r\nbreak", "quote\"", String(repeating: "x", count: 71)] {
            XCTAssertThrowsError(try ChatMultipartBody(files: [url], boundary: boundary))
        }
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try ChatMultipartBody(files: [fifo]))
    }
    func testReplacementBetweenPlanningAndReadingFailsWithoutLeakingPaths() throws {
        let root = try directory(), url = try file(root, "replace.txt", Data("old".utf8))
        let body = try ChatMultipartBody(files: [url], boundary: "fixture")
        try Data("new".utf8).write(to: url, options: .atomic)
        do {
            _ = try drain(body)
            XCTFail("A replaced selected file must not be silently uploaded")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(root.path))
        }
        XCTAssertThrowsError(try body.read())
    }
    func testGrowthAndTruncationAfterPartialReadFailAndCloseReader() throws {
        for grow in [false, true] {
            let url = try file(directory(), "changing.bin", Data(repeating: 65, count: 128))
            let body = try ChatMultipartBody(files: [url], boundary: "fixture")
            var prefix = Data()
            while !prefix.suffix(4).elementsEqual(Data("\r\n\r\n".utf8)) { prefix.append(try XCTUnwrap(body.read(maximum: 1))) }
            XCTAssertEqual(try body.read(maximum: 32), Data(repeating: 65, count: 32))
            let writer = try FileHandle(forWritingTo: url)
            try writer.truncate(atOffset: grow ? 256 : 16)
            try writer.close()
            XCTAssertThrowsError(try body.read())
            XCTAssertThrowsError(try body.read())
        }
    }
    func testLargeContentIsReadInBoundedChunksAndCancelledReaderCannotResume() throws {
        let url = try file(directory(), "large.bin")
        let writer = try FileHandle(forWritingTo: url)
        for _ in 0..<80 { try writer.write(contentsOf: Data(repeating: 65, count: 65536)) }
        try writer.close()
        let body = try ChatMultipartBody(files: [url], boundary: "fixture")
        var total: Int64 = 0, chunks = 0
        while let part = try body.read() {
            XCTAssertLessThanOrEqual(part.count, 65536)
            total += Int64(part.count); chunks += 1
        }
        XCTAssertEqual(total, body.contentLength)
        XCTAssertGreaterThan(chunks, 80)
        let cancelled = try ChatMultipartBody(files: [url])
        _ = try cancelled.read()
        cancelled.close(); cancelled.close()
        XCTAssertThrowsError(try cancelled.read()) { XCTAssertTrue($0 is CancellationError) }
    }
    func testInvalidChunkBoundFailsWithoutReturningUnboundedData() throws {
        let url = try file(directory(), "file")
        for maximum in [0, -1, 65537, Int.max] {
            let body = try ChatMultipartBody(files: [url])
            XCTAssertThrowsError(try body.read(maximum: maximum))
        }
    }
    func testWireMatchesExecutedSecondaryFormDataEncoder() throws {
        struct Reference: Decodable {
            struct Entry: Decodable {
                struct File: Decodable { let name: String; let base64: String }
                let files: [File]; let boundary: String; let wire_base64: String
            }
            let cases: [Entry]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: root.appendingPathComponent("evidence/chat/upload-formdata-reference.json")))
        XCTAssertEqual(reference.cases.count, 3)
        for item in reference.cases {
            let selected = try item.files.map { entry in
                try file(directory(), entry.name, XCTUnwrap(Data(base64Encoded: entry.base64)))
            }
            let body = try ChatMultipartBody(files: selected, boundary: item.boundary)
            XCTAssertEqual(try drain(body, chunk: 17), try XCTUnwrap(Data(base64Encoded: item.wire_base64)))
        }
    }
    func testSameSizeContentChangeWithChangedMetadataFails() throws {
        let url = try file(directory(), "modified.txt", Data("old".utf8))
        let body = try ChatMultipartBody(files: [url])
        let writer = try FileHandle(forWritingTo: url)
        try writer.write(contentsOf: Data("new".utf8)); try writer.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        XCTAssertThrowsError(try drain(body))
    }
    func testCancelledTaskCannotStartOrResumeReader() async throws {
        let url = try file(directory(), "cancelled.txt", Data("test".utf8))
        let task = Task { () throws -> Bool in
            let body = try ChatMultipartBody(files: [url])
            _ = try body.read(maximum: 1)
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try body.read(); return false }
            catch is CancellationError {
                do { _ = try body.read(); return false }
                catch is CancellationError { return true }
            }
        }
        let cancelled = try await task.value
        XCTAssertTrue(cancelled)
    }

}
