import Darwin
import Foundation
import XCTest
@testable import NetworkPNTRCore

private final class DownloadPeer: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var outcome: Result<Void, Error>?
    init(_ fd: Int32, action: @escaping @Sendable (Int32) throws -> Void) {
        DispatchQueue.global().async { [self] in
            defer { Darwin.close(fd); done.signal() }
            let result = Result { try action(fd) }
            lock.lock(); outcome = result; lock.unlock()
        }
    }
    func finish() throws {
        guard done.wait(timeout: .now() + 4) == .success else { throw RuntimeError.timeout("download peer") }
        lock.lock(); defer { lock.unlock() }
        try XCTUnwrap(outcome).get()
    }
}
final class BackendDownloadExchangeTests: XCTestCase {
    private func pair() throws -> (BackendUploadSocket, Int32) {
        var fds: [Int32] = [0,0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw POSIXError(.EIO) }
        var value: Int32 = 1
        XCTAssertEqual(setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size)), 0)
        return (BackendUploadSocket(owning: fds[0]), fds[1])
    }
    private static func write(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw POSIXError(.EIO) }
                offset += n
            }
        }
    }
    private static func readRequest(_ fd: Int32) throws {
        var data = Data(), buffer = [UInt8](repeating: 0, count: 17)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = Darwin.read(fd, &buffer, buffer.count)
            guard n > 0, data.count < 32768 else { throw BackendAPIError.invalidResponse }
            data.append(contentsOf: buffer.prefix(n))
        }
        guard data.starts(with: Data("fixture\nGET /api/".utf8)) else { throw BackendAPIError.invalidResponse }
    }
    private let request = Data("GET /api/workspace/download?path=fixture HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
    func testActualSocketStreamsBeyondJSONLimitAndCompletesWithoutEOF() throws {
        let (socket, fd) = try pair()
        let chunk = Data(repeating: 0xBD, count: 65536), size: Int64 = 6 * 1024 * 1024
        let peer = DownloadPeer(fd) { fd in
            try Self.readRequest(fd)
            let header = Data("HTTP/1.1 200 OK\r\nContent-Length: \(size)\r\n\r\n".utf8)
            for byte in header { try Self.write(fd, Data([byte])) }
            for _ in 0..<96 { try Self.write(fd, chunk) }
            Thread.sleep(forTimeInterval: 0.15)
        }
        let result = try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: size, timeout: .seconds(2))
        XCTAssertEqual(result.byteCount, size)
        XCTAssertEqual(result.sha256, ArtifactIntegrity.sha256(Data(repeating: 0xBD, count: Int(size))))
        XCTAssertTrue(socket.isFinished); try socket.validateCompletion(); try peer.finish()
    }
    func testUnauthorizedBodyReturnsStatusWithoutWaitingForEOF() throws {
        let (socket, fd) = try pair()
        let peer = DownloadPeer(fd) { fd in
            try Self.readRequest(fd)
            try Self.write(fd, Data("HTTP/1.1 401 Denied\r\nContent-Length: 2\r\n\r\n{}".utf8))
            Thread.sleep(forTimeInterval: 0.15)
        }
        XCTAssertEqual(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 9999999, timeout: .seconds(1)).status, 401)
        try peer.finish()
    }
    func testShortAndExtraResponsesCannotReturnDigest() throws {
        for body in ["x", "xyz"] {
            let (socket, fd) = try pair()
            let peer = DownloadPeer(fd) { fd in
                try Self.readRequest(fd)
                try Self.write(fd, Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n\(body)".utf8))
            }
            XCTAssertThrowsError(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 2, timeout: .seconds(1)))
            XCTAssertTrue(socket.isFinished); try peer.finish()
        }
    }
    func testCancellationBeforeAndDuringStalledResponseClosesOwnedDescriptor() throws {
        for before in [true, false] {
            let (socket, fd) = try pair()
            defer { Darwin.close(fd) }
            if before { socket.cancel() }
            else { DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { socket.cancel() } }
            XCTAssertThrowsError(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 5, timeout: .seconds(1))) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertTrue(socket.isFinished)
        }
    }
    func testPrematureSuccessBeforeRequestCannotBeAcceptedButEarly401Can() throws {
        for status in [200,401] {
            let (socket, fd) = try pair()
            defer { Darwin.close(fd) }
            try Self.write(fd, Data("HTTP/1.1 \(status) Fixture\r\nContent-Length: 0\r\n\r\n".utf8))
            if status == 200 {
                XCTAssertThrowsError(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 0, timeout: .seconds(1)))
            } else {
                XCTAssertEqual(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 0, timeout: .seconds(1)).status, 401)
            }
            XCTAssertTrue(socket.isFinished)
        }
    }
    func testFiniteDeadlineAndInvalidInputsReleaseConnection() throws {
        let (socket, fd) = try pair(); defer { Darwin.close(fd) }
        XCTAssertThrowsError(try BackendDownloadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), request: request, expectedSize: 0, timeout: .milliseconds(80))) {
            guard case RuntimeError.timeout = $0 else { return XCTFail("Expected finite timeout") }
        }
        XCTAssertTrue(socket.isFinished)
        let (invalid, other) = try pair(); defer { Darwin.close(other) }
        XCTAssertThrowsError(try BackendDownloadExchange.exchange(socket: invalid, preamble: Data(repeating: 65, count: 257), request: request, expectedSize: 0))
        XCTAssertTrue(invalid.isFinished)
    }
}
