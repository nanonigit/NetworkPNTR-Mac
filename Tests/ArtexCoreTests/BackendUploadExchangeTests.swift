import Darwin
import Foundation
import XCTest
@testable import ArtexCore

private final class UploadPeer: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    init(_ fd: Int32, operation: @escaping @Sendable (Int32) throws -> Data) {
        DispatchQueue.global().async { [self] in
            defer { Darwin.close(fd); done.signal() }
            let outcome = Result { try operation(fd) }
            lock.lock(); result = outcome; lock.unlock()
        }
    }
    func value() throws -> Data {
        guard done.wait(timeout: .now() + 3) == .success else { throw RuntimeError.timeout("test upload peer") }
        lock.lock(); defer { lock.unlock() }
        return try XCTUnwrap(result).get()
    }
}
private final class LockedUploadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value: BackendUploadProgress?
    func record(_ event: BackendUploadProgress) { lock.lock(); value = event; lock.unlock() }
    var last: BackendUploadProgress? { lock.lock(); defer { lock.unlock() }; return value }
}
final class BackendUploadExchangeTests: XCTestCase {
    private func selectedFile(size: Int = 0) throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("artex-upload-exchange-" + UUID().uuidString)
        XCTAssertTrue(FileManager.default.createFile(atPath: path.path, contents: nil))
        let writer = try FileHandle(forWritingTo: path)
        try writer.truncate(atOffset: UInt64(size)); try writer.close()
        addTeardownBlock { try FileManager.default.removeItem(at: path) }
        return path
    }
    private func pair() throws -> (BackendUploadSocket, Int32) {
        var fds: [Int32] = [0,0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw POSIXError(.EIO) }
        var enabled: Int32 = 1
        XCTAssertEqual(setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)), 0)
        var buffer: Int32 = 1024
        XCTAssertEqual(setsockopt(fds[0], SOL_SOCKET, SO_SNDBUF, &buffer, socklen_t(MemoryLayout<Int32>.size)), 0)
        return (BackendUploadSocket(owning: fds[0]), fds[1])
    }
    private static func receive(_ fd: Int32, count: Int) throws -> Data {
        var output = Data(), chunk = [UInt8](repeating: 0, count: 4096)
        while output.count < count {
            let n = Darwin.read(fd, &chunk, min(chunk.count, count - output.count))
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { throw RuntimeError.integrity("test peer short read") }
            output.append(contentsOf: chunk.prefix(n))
        }
        return output
    }
    @discardableResult private static func write(_ fd: Int32, _ bytes: Data) throws -> Int {
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += n
            }
            return offset
        }
    }
    func testImmutablePlanProducesSameFramingAndValidatesRouteAndBearer() throws {
        let url = try selectedFile(size: 7), plan = try ChatMultipartPlan(files: [url], boundary: "fixture")
        let body = ChatMultipartBody(plan: plan)
        XCTAssertEqual(body.contentLength, plan.contentLength)
        let header = try BackendMultipartRequest.header(conversationID: 42, plan: plan, bearer: "fixture.jwt")
        let text = String(decoding: header, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("POST /api/chat/upload?scope=session&id=conv-42 HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("Content-Length: \(plan.contentLength)\r\n"))
        XCTAssertTrue(text.contains("Content-Type: multipart/form-data; boundary=fixture\r\n"))
        XCTAssertTrue(text.contains("Authorization: Bearer fixture.jwt\r\n"))
        for id: Int64 in [0,-1] { XCTAssertThrowsError(try BackendMultipartRequest.header(conversationID: id, plan: plan, bearer: "fixture.jwt")) }
        for token in ["", "bad\r\nInjected: yes", "bad space", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try BackendMultipartRequest.header(conversationID: 42, plan: plan, bearer: token))
        }
    }
    func testNonblockingPartialWritesAndDelayedReadTransferEntireBody() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile(size: 5 * 1024 * 1024)], boundary: "fixture")
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
        let preamble = Data("fixture-transport\n".utf8), expected = Int(plan.contentLength) + header.count + preamble.count
        let (socket, server) = try pair()
        let peer = UploadPeer(server) { fd in
            Thread.sleep(forTimeInterval: 0.03)
            let received = try Self.receive(fd, count: expected)
            try Self.write(fd, Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8))
            return received
        }
        let response = try BackendUploadExchange.exchange(socket: socket, preamble: preamble, header: header, plan: plan, timeout: .seconds(2))
        XCTAssertEqual(response.status, 200); XCTAssertEqual(response.body, Data("{}".utf8))
        let wire = try peer.value()
        XCTAssertEqual(wire.count, expected)
        XCTAssertTrue(wire.starts(with: preamble + header))
        XCTAssertTrue(wire.suffix(15).elementsEqual(Data("\r\n--fixture--\r\n".utf8)))
        XCTAssertTrue(socket.isFinished)
    }
    func testCancellationWitnessCountsOnlyOpenUncancelledOwner() throws {
        let (socket, peer) = try pair(); defer { Darwin.close(peer) }
        XCTAssertTrue(socket.cancel())
        XCTAssertFalse(socket.cancel())
        socket.finish()
        XCTAssertFalse(socket.cancel())
        let (finished, other) = try pair(); defer { Darwin.close(other) }
        finished.finish()
        XCTAssertFalse(finished.cancel())
    }
    func testProgressCountsOnlyBodyAndCanCancelActualSocketBeforeFullPayload() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile(size: 120 * 1024 * 1024)])
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
        let (socket, server) = try pair()
        let peer = UploadPeer(server) { fd in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while Darwin.read(fd, &buffer, buffer.count) > 0 { }
            return Data()
        }
        let progress = LockedUploadProgress()
        XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data("fixture\n".utf8), header: header, plan: plan, timeout: .seconds(2), progress: { event in
            progress.record(event)
            socket.cancel()
        })) { XCTAssertTrue($0 is CancellationError) }
        let event = try XCTUnwrap(progress.last)
        XCTAssertGreaterThan(event.sentBodyBytes, 0)
        XCTAssertLessThanOrEqual(event.sentBodyBytes, 65536)
        XCTAssertEqual(event.totalBodyBytes, plan.contentLength)
        XCTAssertLessThan(event.sentBodyBytes, event.totalBodyBytes)
        XCTAssertTrue(socket.isFinished)
        _ = try peer.value()
    }
    func testEarlyUnauthorizedResponseDoesNotRequireSendingEntireLargeFile() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile(size: 120 * 1024 * 1024)])
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "expired.jwt")
        let (socket, server) = try pair()
        let peer = UploadPeer(server) { fd in
            _ = try Self.receive(fd, count: header.count)
            try Self.write(fd, Data("HTTP/1.1 401 Unauthorized\r\nContent-Length: 2\r\n\r\n{}".utf8))
            return Data()
        }
        XCTAssertEqual(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1)).status, 401)
        _ = try peer.value(); XCTAssertTrue(socket.isFinished)
    }
    func testCancellationDuringBlockedWriteAndBeforeStartClosesOwnedSocket() throws {
        for beforeStart in [false, true] {
            let plan = try ChatMultipartPlan(files: [selectedFile(size: 8 * 1024 * 1024)])
            let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
            let (socket, server) = try pair()
            let peer = UploadPeer(server) { _ in
                if !beforeStart { Thread.sleep(forTimeInterval: 0.04); socket.cancel() }
                return Data()
            }
            if beforeStart { socket.cancel() }
            XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1))) {
                XCTAssertTrue($0 is CancellationError)
            }
            _ = try peer.value(); XCTAssertTrue(socket.isFinished)
        }
    }
    func testCancellationDuringResponseWaitClosesOwnedSocket() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile()])
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
        let expected = header.count + Int(plan.contentLength), (socket, server) = try pair()
        let peer = UploadPeer(server) { fd in
            _ = try Self.receive(fd, count: expected)
            socket.cancel()
            return Data()
        }
        XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1))) { XCTAssertTrue($0 is CancellationError) }
        _ = try peer.value(); XCTAssertTrue(socket.isFinished)
    }
    func testDeadlineExpiresForStalledPeer() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile(size: 8 * 1024 * 1024)])
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
        let (socket, server) = try pair(), release = DispatchSemaphore(value: 0)
        let peer = UploadPeer(server) { _ in _ = release.wait(timeout: .now() + 2); return Data() }
        defer { release.signal() }
        XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .milliseconds(60))) {
            guard case RuntimeError.timeout = $0 else { return XCTFail("Expected a transfer deadline") }
        }
        release.signal(); _ = try peer.value(); XCTAssertTrue(socket.isFinished)
    }
    func testPrematureSuccessMalformedAndOversizedResponsesAreRejected() throws {
        for reply in [Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8), Data("invalid\r\n\r\n".utf8), Data("HTTP/1.1 401 Unauthorized\r\nContent-Length: 4194305\r\n\r\n".utf8) + Data(repeating: 65, count: 4 * 1024 * 1024 + 1)] {
            let plan = try ChatMultipartPlan(files: [selectedFile(size: 8 * 1024 * 1024)])
            let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
            let (socket, server) = try pair()
            let peer = UploadPeer(server) { fd in
                _ = try Self.receive(fd, count: header.count)
                do { try Self.write(fd, reply) }
                catch let error as POSIXError where [.EPIPE,.ECONNRESET].contains(error.code) { }
                return Data()
            }
            XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1)))
            _ = try peer.value(); XCTAssertTrue(socket.isFinished)
        }
    }
    private func tcpPair() throws -> (BackendUploadSocket, Int32) {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, length) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { throw POSIXError(.EIO) }
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        guard named == 0 else { throw POSIXError(.EIO) }
        let client = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard client >= 0 else { throw POSIXError(.EIO) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, length) }
        }
        guard connected == 0 else { Darwin.close(client); throw POSIXError(.EIO) }
        let server = accept(listener, nil, nil)
        guard server >= 0 else { Darwin.close(client); throw POSIXError(.EIO) }
        var enabled: Int32 = 1
        XCTAssertEqual(setsockopt(server, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)), 0)
        var abortive = linger(l_onoff: 1, l_linger: 0)
        XCTAssertEqual(setsockopt(server, SOL_SOCKET, SO_LINGER, &abortive, socklen_t(MemoryLayout<linger>.size)), 0)
        return (BackendUploadSocket(owning: client), server)
    }
    func testCompleteEarlyErrorSurvivesResetWithUnreadUploadBytes() throws {
        for status in [401,413] {
            let plan = try ChatMultipartPlan(files: [selectedFile(size: 120 * 1024 * 1024)])
            let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
            let (socket, server) = try tcpPair()
            let peer = UploadPeer(server) { fd in
                _ = try Self.receive(fd, count: header.count)
                try Self.write(fd, Data("HTTP/1.1 \(status) Rejected\r\nContent-Length: 2\r\n\r\n{}".utf8))
                return Data() // SO_LINGER=0 resets with the remainder of the upload unread.
            }
            let response = try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1))
            XCTAssertEqual(response.status, status)
            _ = try peer.value(); XCTAssertTrue(socket.isFinished)
        }
    }
    func testCompleteFramedEarlyResponseDoesNotWaitForEOF() throws {
        for chunked in [false,true] {
            let plan = try ChatMultipartPlan(files: [selectedFile(size: 8 * 1024 * 1024)])
            let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
            let (socket, server) = try pair(), release = DispatchSemaphore(value: 0)
            let peer = UploadPeer(server) { fd in
                _ = try Self.receive(fd, count: header.count)
                let framing = chunked ? "Transfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n" : "Content-Length: 2\r\n\r\n{}"
                try Self.write(fd, Data(("HTTP/1.1 401 Rejected\r\n" + framing).utf8))
                _ = release.wait(timeout: .now() + 2)
                return Data()
            }
            defer { release.signal() }
            let response = try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .milliseconds(100))
            XCTAssertEqual(response.status, 401); XCTAssertEqual(response.body, Data("{}".utf8))
            release.signal(); _ = try peer.value()
        }
    }
    func testTruncatedAndAmbiguousEarlyResponsesCannotBecomeSuccessfulResults() throws {
        for framing in ["Content-Length: 4\r\n\r\n{}", "Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}", "Transfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n", "Transfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}"] {
            let plan = try ChatMultipartPlan(files: [selectedFile(size: 8 * 1024 * 1024)])
            let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
            let (socket, server) = try pair()
            let peer = UploadPeer(server) { fd in
                _ = try Self.receive(fd, count: header.count)
                try Self.write(fd, Data(("HTTP/1.1 401 Rejected\r\n" + framing).utf8))
                return Data()
            }
            XCTAssertThrowsError(try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan, timeout: .seconds(1)))
            _ = try peer.value()
        }
    }

    func testCompletedExchangeCannotPassCancelledTransferLease() throws {
        let plan = try ChatMultipartPlan(files: [selectedFile()])
        let header = try BackendMultipartRequest.header(conversationID: 1, plan: plan, bearer: "fixture.jwt")
        let (socket, server) = try pair(), expected = header.count + Int(plan.contentLength)
        let peer = UploadPeer(server) { fd in
            _ = try Self.receive(fd, count: expected)
            try Self.write(fd, Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8))
            return Data()
        }
        let response = try BackendUploadExchange.exchange(socket: socket, preamble: Data(), header: header, plan: plan)
        XCTAssertEqual(response.status, 200); XCTAssertTrue(socket.isFinished)
        XCTAssertNoThrow(try socket.validateCompletion())
        // The runtime stop/caller-cancel signal may arrive after worker EOF,
        // while the main actor still has not accepted the completed response.
        socket.cancel()
        XCTAssertThrowsError(try socket.validateCompletion()) { XCTAssertTrue($0 is CancellationError) }
        _ = try peer.value()
    }

}
