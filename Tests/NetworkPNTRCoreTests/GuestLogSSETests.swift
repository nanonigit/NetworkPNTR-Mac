#if DEBUG
import Darwin
import XCTest
@testable import NetworkPNTRCore

final class GuestLogSSETests: XCTestCase {
    func testSplitHeadersAndEventsReportHeartbeatWithoutAddingARow() throws {
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
        var heartbeats = 0
        for byte in wire.utf8 {
            let batch = try decoder.consume(Data([byte]))
            entries += batch.rows
            if batch.hasHeartbeat { heartbeats += 1 }
        }
        XCTAssertEqual(heartbeats, 1)
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
            rows += batch.rows
            if batch.hasHeartbeat {
                XCTAssertEqual(rows.map(\.seq), [1])
                let written = next.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count) }
                XCTAssertEqual(written, next.count)
                return true
            }
            if rows.count == 1 {
                let heartbeat = Data(": ping\n\n".utf8)
                let written = heartbeat.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count) }
                XCTAssertEqual(written, heartbeat.count)
                return true
            }
            return false
        }
        XCTAssertEqual(rows.map(\.seq), [1, 2])
        XCTAssertTrue(socket.isFinished)
    }

    @MainActor func testFollowRecoversBurstBetweenSocketConnections() async throws {
        let transport = ChatTestTransport()
        let store = GuestLogStore(service: GuestLogService(client: transport))
        try transport.enqueue(["items": [burstRow(1)], "cursor": 1])
        try transport.enqueue(["items": (203...1202).map(burstRow), "cursor": 1202])
        try transport.enqueue(["items": (3...1202).map(burstRow), "cursor": 1202])

        var opened: [Int64] = []
        var receivedRequests: [String] = []
        let follow = Task {
            await store.follow { since, receive in
                opened.append(since)
                switch opened.count {
                case 1:
                    receivedRequests.append(try await runClosedPeer(since: since, sequences: [2], receive: receive))
                case 2:
                    receivedRequests.append(try await runClosedPeer(since: since, sequences: [1202, 1203], receive: receive))
                    throw CancellationError()
                default:
                    XCTFail("The stream opened more than twice")
                    throw CancellationError()
                }
            }
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(8))
            follow.cancel()
        }
        defer { deadline.cancel() }
        await follow.value

        XCTAssertEqual(opened, [1, 1202])
        XCTAssertEqual(receivedRequests, [
            "GET /api/logs/stream?since=1 HTTP/1.0",
            "GET /api/logs/stream?since=1202 HTTP/1.0"
        ])
        XCTAssertEqual(transport.calls.map(\.path), [
            "/api/logs?since=0&limit=1000", "/api/logs?since=2&limit=1000", "/api/logs?since=2&limit=3000"
        ])
        XCTAssertEqual(store.rows.map(\.seq), (1...1203).map(Int64.init))
        XCTAssertFalse(store.liveHistoryGap)
        XCTAssertNil(store.recentFailure)
    }

    @MainActor private func runClosedPeer(since: Int64, sequences: [Int], receive: @escaping GuestLogBatchReceiver) async throws -> String {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        let peer = descriptors[1]
        defer { Darwin.close(peer) }
        let socket = BackendUploadSocket(owning: descriptors[0])
        var wire = Data("HTTP/1.0 200 OK\r\nContent-Type: text/event-stream\r\n\r\n".utf8)
        for sequence in sequences {
            wire.append(Data("data: ".utf8))
            wire.append(try JSONSerialization.data(withJSONObject: burstRow(sequence)))
            wire.append(Data("\n\n".utf8))
        }
        let written = wire.withUnsafeBytes { Darwin.write(peer, $0.baseAddress!, $0.count) }
        guard written == wire.count, shutdown(peer, SHUT_WR) == 0 else { throw POSIXError(.EIO) }
        let request = try BackendHTTPRequest.guestLogStream(since: since, bearer: "fixture")
        try await GuestLogSSEExchange.stream(socket: socket, request: request, timeout: .seconds(2), receive: receive)
        XCTAssertTrue(socket.isFinished)
        var bytes = [UInt8](repeating: 0, count: 1024)
        let read = Darwin.read(peer, &bytes, bytes.count)
        guard read > 0 else { throw POSIXError(.EIO) }
        let firstLine = String(decoding: bytes.prefix(read), as: UTF8.self).components(separatedBy: "\r\n").first
        return try XCTUnwrap(firstLine)
    }

    private func burstRow(_ sequence: Int) -> [String: Any] {
        ["seq": sequence, "ts": "fixture", "level": "info", "tag": "fixture", "text": "line \(sequence)"]
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
