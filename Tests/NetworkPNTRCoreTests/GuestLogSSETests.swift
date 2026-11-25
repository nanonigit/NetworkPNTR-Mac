#if DEBUG
import Darwin
import XCTest
@testable import NetworkPNTRCore

final class GuestLogSSETests: XCTestCase {
    func testSplitHeadersAndEventsDeliverBeforeEOFAndIgnoreHeartbeat() throws {
        var decoder = GuestLogSSEDecoder()
        let wire = """
        HTTP/1.0 200 OK\r
        Content-Type: text/event-stream\r
        \r
        : ping

        data: {"seq":41,"ts":"2026-11-25T01:00:00Z","level":"info","tag":"fixture","text":"日本語"}\r
        \r

        """
        var entries: [GuestLogEntry] = []
        for byte in wire.utf8 { entries += try decoder.consume(Data([byte])) }
        XCTAssertEqual(entries.map(\.seq), [41])
        XCTAssertEqual(entries.first?.text, "日本語")
    }

    func testHTTPStatusFramingAndIncompleteSizeAreRejected() throws {
        var unauthorized = GuestLogSSEDecoder()
        XCTAssertThrowsError(try unauthorized.consume(Data("HTTP/1.0 401 Unauthorized\r\nContent-Length: 19\r\n\r\n".utf8))) {
            guard case BackendAPIError.status(401) = $0 else { return XCTFail("Wrong rejection") }
        }
        var chunked = GuestLogSSEDecoder()
        XCTAssertThrowsError(try chunked.consume(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)))
        var oversized = GuestLogSSEDecoder()
        XCTAssertThrowsError(try oversized.consume(Data(repeating: 65, count: 17_000)))
    }

    @MainActor func testSocketSampleCompletesWhilePeerIsStillOpen() async throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        let peer = descriptors[1]
        defer { Darwin.close(peer) }
        let socket = BackendUploadSocket(owning: descriptors[0])
        let wire = Data(("HTTP/1.0 200 OK\r\nContent-Type: text/event-stream\r\n\r\n" +
            "data: {\"seq\":1,\"ts\":\"fixture\",\"level\":\"info\",\"tag\":\"fixture\",\"text\":\"fixture\"}\n\n").utf8)
        let written = wire.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count) }
        XCTAssertEqual(written, wire.count)
        var rows: [GuestLogEntry] = []
        let next = Data("data: {\"seq\":2,\"ts\":\"fixture\",\"level\":\"info\",\"tag\":\"fixture\",\"text\":\"next\"}\n\n".utf8)
        try await GuestLogSSEExchange.stream(socket: socket, request: Data("fixture".utf8), timeout: .seconds(2)) { batch in
            rows += batch
            if rows.count == 1 {
                let written = next.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count) }
                XCTAssertEqual(written, next.count)
                return true
            }
            return false
        }
        XCTAssertEqual(rows.map(\.seq), [1, 2])
        XCTAssertTrue(socket.isFinished)
    }

    func testRequestTargetsOnlyLogsAndUsesHeaderForBearer() throws {
        let request = try BackendHTTPRequest.guestLogStream(since: 42, bearer: "test-fixture")
        let line = String(decoding: request, as: UTF8.self)
        XCTAssertTrue(line.hasPrefix("GET /api/logs/stream?since=42 HTTP/1.0\r\n"))
        XCTAssertTrue(line.contains("Accept: text/event-stream\r\n"))
        XCTAssertTrue(line.contains("Authorization: Bearer test-fixture\r\n"))
        XCTAssertFalse(line.contains("?token="))
        XCTAssertThrowsError(try BackendHTTPRequest.guestLogStream(since: -1, bearer: "test"))
        XCTAssertThrowsError(try BackendHTTPRequest.guestLogStream(since: 0, bearer: "test\r\nheader"))
    }
}
#endif
