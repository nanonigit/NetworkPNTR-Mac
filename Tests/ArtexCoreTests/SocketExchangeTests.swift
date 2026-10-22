import Darwin
import XCTest
@testable import ArtexCore

final class SocketExchangeTests: XCTestCase {
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
