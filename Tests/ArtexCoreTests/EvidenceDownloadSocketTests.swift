import Darwin
import Foundation
import XCTest
@testable import ArtexCore

private final class EvidenceSocketPeer: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0), lock = NSLock()
    private var outcome: Result<Void, any Error>?
    init(_ fd: Int32, action: @escaping @Sendable (Int32) throws -> Void) {
        DispatchQueue.global().async { [self] in
            defer { Darwin.close(fd); done.signal() }
            let result = Result { try action(fd) }
            lock.lock(); outcome = result; lock.unlock()
        }
    }
    func finish() throws {
        guard done.wait(timeout: .now() + 10) == .success else { throw RuntimeError.timeout("evidence socket peer") }
        lock.lock(); defer { lock.unlock() }
        try XCTUnwrap(outcome).get()
    }
}
final class EvidenceDownloadSocketTests: XCTestCase {
    private func pair() throws -> (BackendUploadSocket, Int32) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw POSIXError(.EIO) }
        var value: Int32 = 1
        XCTAssertEqual(setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size)), 0)
        return (BackendUploadSocket(owning: fds[0]), fds[1])
    }
    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("artex-evidence-socket-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
        return value
    }
    private func spec(_ data: Data) throws -> FindingEvidenceDownload {
        try .init(findingID: "9101", bindingID: "1", side: .response, expectedSize: Int64(data.count), expectedSHA256: ArtifactIntegrity.sha256(data))
    }
    private static func write(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw POSIXError(.EIO) }; offset += n
            }
        }
    }
    private static func request(_ fd: Int32) throws {
        var data = Data(), bytes = [UInt8](repeating: 0, count: 127)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = Darwin.read(fd, &bytes, bytes.count)
            guard n > 0, data.count < 32768 else { throw BackendAPIError.invalidResponse }
            data.append(contentsOf: bytes.prefix(n))
        }
        guard data.starts(with: Data("fixture\nGET /api/exploration/findings/9101/traffic/1/body?".utf8)) else { throw BackendAPIError.invalidResponse }
    }
    func testActualSocketStagesAndPublishesFullBinaryBeyondJSONLimit() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0xBD, count: 6 * 1024 * 1024), manifest = try spec(bytes)
        let (socket, fd) = try pair()
        let peer = EvidenceSocketPeer(fd) { fd in
            try Self.request(fd)
            try Self.write(fd, Data("HTTP/1.1 200 OK\r\nContent-Length: \(bytes.count)\r\n\r\n".utf8))
            for start in stride(from: 0, to: bytes.count, by: 65536) { try Self.write(fd, bytes.subdata(in: start..<min(start + 65536, bytes.count))) }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let response = try EvidenceDownloadStaging.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: manifest.request(bearer: "fixture.jwt"), manifest: manifest, destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), timeout: .seconds(5))
        let file = try XCTUnwrap(response.file); let saved = try file.commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), bytes); XCTAssertEqual(response.result.byteCount, Int64(bytes.count))
        XCTAssertTrue(saved.stagingCleanupComplete); XCTAssertTrue(socket.isFinished); try peer.finish()
    }
    func testUnauthorizedResponseNeverWritesErrorBodyOrLeavesStaging() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try spec(Data([1, 2, 3])); let (socket, fd) = try pair()
        let peer = EvidenceSocketPeer(fd) { fd in
            try Self.request(fd); try Self.write(fd, Data("HTTP/1.1 401 Denied\r\nContent-Length: 2\r\n\r\n{}".utf8))
        }
        let response = try EvidenceDownloadStaging.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: manifest.request(bearer: "fixture.jwt"), manifest: manifest, destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), timeout: .seconds(5))
        XCTAssertEqual(response.result.status, 401); XCTAssertNil(response.file)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty); try peer.finish()
    }
    func testTruncationWrongHashAndWrongLengthRemoveAllPartialBytes() throws {
        for mode in 0..<3 {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let manifest = try spec(Data([1, 2, 3])); let (socket, fd) = try pair()
            let peer = EvidenceSocketPeer(fd) { fd in
                try Self.request(fd)
                let data = mode == 0 ? Data([1]) : mode == 1 ? Data([4, 5, 6]) : Data([1, 2, 3])
                let length = mode == 2 ? 4 : 3
                try Self.write(fd, Data("HTTP/1.1 200 OK\r\nContent-Length: \(length)\r\n\r\n".utf8) + data)
            }
            XCTAssertThrowsError(try EvidenceDownloadStaging.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: manifest.request(bearer: "fixture.jwt"), manifest: manifest, destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), timeout: .seconds(5)))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty); XCTAssertTrue(socket.isFinished); try peer.finish()
        }
    }
    func testCancellationBeforeAndDuringStallAndDeadlineDiscardPartialState() throws {
        for mode in 0..<3 {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let manifest = try spec(Data([1, 2, 3])); let (socket, fd) = try pair(); defer { Darwin.close(fd) }
            if mode == 0 { socket.cancel() }
            if mode == 1 { DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { socket.cancel() } }
            XCTAssertThrowsError(try EvidenceDownloadStaging.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: manifest.request(bearer: "fixture.jwt"), manifest: manifest, destination: EvidenceExportDestination(newFileURL: root.appendingPathComponent("output.bin")), timeout: .milliseconds(100)))
            XCTAssertTrue(socket.isFinished); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    func testRacingExistingDestinationFailsBeforeAnyRequestBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("output.bin"), destination = try EvidenceExportDestination(newFileURL: url)
        let sentinel = Data("keep".utf8); try sentinel.write(to: url)
        let manifest = try spec(Data([1])); let (socket, fd) = try pair(); defer { Darwin.close(fd) }
        XCTAssertThrowsError(try EvidenceDownloadStaging.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: manifest.request(bearer: "fixture.jwt"), manifest: manifest, destination: destination, timeout: .milliseconds(100)))
        var buffer = [UInt8](repeating: 0, count: 1024)
        XCTAssertEqual(Darwin.read(fd, &buffer, buffer.count), 0)
        XCTAssertEqual(try Data(contentsOf: url), sentinel); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["output.bin"])
    }
}
