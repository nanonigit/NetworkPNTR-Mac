import Darwin
import XCTest
@testable import NetworkPNTRCore

final class SocketExchangeTests: XCTestCase {
    func testCancellationClosesAnInFlightJSONReadBeforeThePeerResponds() async throws {
        var pair: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            return XCTFail("socketpair")
        }
        let socket = BackendUploadSocket(owning: pair[0])
        let server = pair[1]
        defer { close(server) }
        let request = Data("request".utf8)
        let exchange = Task { try await BackendSocketExchange.exchange(socket: socket, request: request) }
        defer { exchange.cancel() }
        var readable = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
        guard poll(&readable, 1, 2000) == 1 else { return XCTFail("request did not reach peer") }
        var bytes = [UInt8](repeating: 0, count: request.count)
        XCTAssertEqual(read(server, &bytes, bytes.count), request.count)
        XCTAssertEqual(Data(bytes), request)

        exchange.cancel()
        readable.revents = 0
        guard poll(&readable, 1, 2000) == 1 else { return XCTFail("cancel did not unblock the socket") }
        XCTAssertEqual(read(server, &bytes, bytes.count), 0)
        do {
            _ = try await exchange.value
            XCTFail("Cancelled JSON exchange returned a response")
        } catch is CancellationError {}
        XCTAssertTrue(socket.isFinished)
    }

    func testNonblockingDescriptorWaitsForDelayedResponse() throws {
        var pair: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        let client = pair[0]; let server = pair[1]
        defer { close(client) }
        XCTAssertEqual(fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK), 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { close(server); finished.signal() }
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = read(server, &bytes, bytes.count)
            Thread.sleep(forTimeInterval: 0.05)
            _ = Data("delayed-response".utf8).withUnsafeBytes { write(server, $0.baseAddress, $0.count) }
        }
        let response = try BackendSocketExchange.exchange(descriptor: client, request: Data("request".utf8))
        XCTAssertEqual(response, Data("delayed-response".utf8))
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
    }
}
