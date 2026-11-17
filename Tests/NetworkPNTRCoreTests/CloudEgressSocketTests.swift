import Darwin
import Foundation
import XCTest
@testable import NetworkPNTRCore

final class CloudEgressSocketTests: XCTestCase {
    @MainActor func testInactiveControllerRejectsEnable() async {
        let controller = VMController()
        XCTAssertThrowsError(try controller.enableCloudEgress())
        XCTAssertFalse(controller.hasMachine)
    }

    func testRequestAndResponseAcrossRealSocketPair() throws {
        let (server, guest) = try sockets()
        defer { Darwin.close(guest) }
        let session = CloudEgressSocketSession(owning: server) { request, _, _, emit in
            guard request.route == .geminiChat, request.body == Data("{}".utf8),
                  String(decoding: request.header, as: UTF8.self).contains("Authorization: Bearer fixture\r\n") else {
                throw CloudEgressError.invalidRequest
            }
            try emit(.head(status: 200, type: .eventStream))
            try emit(.body(Data("abc".utf8)))
            try emit(.end)
        }
        let done = launch(session)
        try send(guest, request(route: 7, flags: 1, body: "{}"))
        XCTAssertEqual(try response(guest), Data([1,0,0,0,3,0,200,2, 2,0,0,0,3,97,98,99, 3,0,0,0,0]))
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testInvalidLengthOrTargetNeverInvokesUpstream() throws {
        let requests = [
            request(route: 255), request(route: 1, flags: 1), request(route: 6, reserved: 1),
            request(route: 6, key: "bad\r\nkey"), request(route: 7, bodyLength: 16 * 1024 * 1024 + 1),
            request(route: 7, body: "{}") + Data("unexpected".utf8)
        ]
        for wire in requests {
            let (server, guest) = try sockets()
            defer { Darwin.close(guest) }
            let reached = DispatchSemaphore(value: 0)
            let session = CloudEgressSocketSession(owning: server) { _, _, _, _ in reached.signal() }
            let done = launch(session)
            try send(guest, wire)
            XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(reached.wait(timeout: .now()), .timedOut)
        }
    }

    func testPartialResponseOnUpstreamErrorHasNoTerminal() throws {
        let (server, guest) = try sockets()
        defer { Darwin.close(guest) }
        let session = CloudEgressSocketSession(owning: server) { _, _, _, emit in
            try emit(.head(status: 200, type: .json))
            try emit(.body(Data([0x61])))
            throw CloudEgressTransportError.transferFailed
        }
        let done = launch(session)
        try send(guest, request(route: 1))
        XCTAssertEqual(try response(guest), Data([1,0,0,0,3,0,200,1, 2,0,0,0,1,97]))
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testStopAndPeerDisconnectCancelAnActiveUpstream() throws {
        for interruption in 0..<3 {
            let (server, guest) = try sockets()
            defer { Darwin.close(guest) }
            let entered = DispatchSemaphore(value: 0)
            let cancelled = DispatchSemaphore(value: 0)
            let session = CloudEgressSocketSession(owning: server) { _, token, _, _ in
                entered.signal()
                let deadline = ContinuousClock.now + .seconds(2)
                while !token.isCancelled && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
                if token.isCancelled { cancelled.signal() }
            }
            let done = launch(session)
            try send(guest, request(route: 1))
            XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
            switch interruption {
            case 0: session.cancel()
            case 1: _ = shutdown(guest, SHUT_RDWR)
            default: try send(guest, Data([0x61]))
            }
            XCTAssertEqual(cancelled.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        }
    }

    func testStopInterruptsBackpressuredGuestWriter() throws {
        let (server, guest) = try sockets()
        defer { Darwin.close(guest) }
        var size: Int32 = 4096
        XCTAssertEqual(setsockopt(server, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size)), 0)
        let writing = DispatchSemaphore(value: 0)
        let interrupted = DispatchSemaphore(value: 0)
        let session = CloudEgressSocketSession(owning: server) { _, _, _, emit in
            try emit(.head(status: 200, type: .json))
            writing.signal()
            let chunk = Data(repeating: 65, count: 16384)
            do {
                for _ in 0..<64 { try emit(.body(chunk)) }
            } catch {
                interrupted.signal()
                throw error
            }
        }
        let done = launch(session)
        try send(guest, request(route: 1))
        XCTAssertEqual(writing.wait(timeout: .now() + 2), .success)
        session.cancel()
        XCTAssertEqual(interrupted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testAdmissionLimitsWorkersUntilRelease() {
        let admission = CloudEgressAdmission()
        for _ in 0..<4 { XCTAssertTrue(admission.acquire()) }
        XCTAssertFalse(admission.acquire())
        admission.release()
        XCTAssertTrue(admission.acquire())
        XCTAssertFalse(admission.acquire())
        for _ in 0..<4 { admission.release() }
    }

    private func request(route: UInt8, flags: UInt8 = 0, reserved: UInt8 = 0, key: String = "fixture",
                         body: String = "", bodyLength: UInt32? = nil) -> Data {
        let length = bodyLength ?? UInt32(body.utf8.count)
        let count = UInt16(key.utf8.count)
        return Data([65,82,88,69,1,route,flags,reserved,UInt8(count >> 8),UInt8(truncatingIfNeeded: count),
                     UInt8(length >> 24),UInt8(truncatingIfNeeded: length >> 16),
                     UInt8(truncatingIfNeeded: length >> 8),UInt8(truncatingIfNeeded: length)])
            + Data(key.utf8) + Data(body.utf8)
    }

    private func sockets() throws -> (Int32, Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        if setsockopt(descriptors[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) != 0 {
            descriptors.forEach { Darwin.close($0) }
            throw POSIXError(.EIO)
        }
        return (descriptors[0], descriptors[1])
    }

    private func launch(_ session: CloudEgressSocketSession) -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { session.run(); done.signal() }
        return done
    }

    private func send(_ fd: Int32, _ data: Data) throws {
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count else { throw POSIXError(.EIO) }
    }

    private func response(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else { throw POSIXError(.EIO) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
