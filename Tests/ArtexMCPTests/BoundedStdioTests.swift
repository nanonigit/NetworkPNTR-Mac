import Foundation
import Darwin
import XCTest
@testable import ArtexMCP

final class BoundedStdioTests: XCTestCase {
    func testFragmentedLinesAndEOF() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let stream = await transport.receive()
        let text = Data("{\"text\":\"日本語\"}".utf8)
        try input.fileHandleForWriting.write(contentsOf: text.prefix(12))
        try input.fileHandleForWriting.write(contentsOf: text.suffix(from: 12) + Data([10]))
        try input.fileHandleForWriting.close()
        var items: [Data] = []
        for try await data in stream { items.append(data) }
        XCTAssertEqual(items, [text])
        await transport.disconnect()
    }

    func testOversizedIncompleteLineFailsWithoutWaitingForNewline() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let stream = await transport.receive()
        try input.fileHandleForWriting.write(contentsOf: Data(repeating: 32, count: 65_537))
        do { for try await _ in stream {}; XCTFail("Oversized frame accepted") } catch {}
        await transport.disconnect()
    }

    func testEOFWithPartialLineFails() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let stream = await transport.receive()
        try input.fileHandleForWriting.write(contentsOf: Data("{\"partial\":".utf8))
        try input.fileHandleForWriting.close()
        do { for try await _ in stream {}; XCTFail("Truncated frame accepted") } catch {}
        await transport.disconnect()
    }

    func testOutputIsOneNewlineDelimitedFrame() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        try await transport.send(Data("{\"id\":1}".utf8))
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 1_000)
        XCTAssertEqual(ready, 1)
        if ready == 1 {
            var bytes = [UInt8](repeating: 0, count: 1_024)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            XCTAssertGreaterThan(count, 0)
            if count > 0 { XCTAssertEqual(Data(bytes.prefix(count)), Data("{\"id\":1}\n".utf8)) }
        }
        await transport.disconnect()
    }

    func testQueuedFramesAreBounded() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        try input.fileHandleForWriting.write(contentsOf: Data(String(repeating: "{}\n", count: 33).utf8))
        try await Task.sleep(for: .milliseconds(100))
        let stream = await transport.receive()
        var count = 0
        do { for try await _ in stream { count += 1 }; XCTFail("Queue overflow accepted") } catch {}
        XCTAssertEqual(count, 32)
        await transport.disconnect()
    }

    func testFIFOConnectionFileDoesNotBlockHelperStartup() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/artex-mcp-fifo-" + UUID().uuidString)
        XCTAssertEqual(mkdir(directory.path, 0o700), 0)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("connection.json")
        XCTAssertEqual(mkfifo(file.path, 0o600), 0)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = root.appendingPathComponent(".build/debug/ArtexMCP")
        process.arguments = ["--connection-file", file.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        let deadline = ContinuousClock.now + .seconds(2)
        while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let blocked = process.isRunning
        if blocked { kill(process.processIdentifier, SIGKILL) }
        while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(blocked, "FIFO blocked helper startup")
        XCTAssertEqual(process.terminationStatus, 1)
    }

    func testPartialOutputFailureIsTerminalForLaterSends() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor,
                                             writeTimeout: .milliseconds(100))
        try await transport.connect()
        do { try await transport.send(Data(repeating: 32, count: 1_048_576)); XCTFail("Stalled write succeeded") } catch {}
        do { try await transport.send(Data("{\"id\":2}".utf8)); XCTFail("Partial line reused") } catch {}
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&descriptor, 1, 1_000), 1)
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
        XCTAssertGreaterThan(count, 0)
        await transport.disconnect()
    }

    func testNinthRequestIsRejectedWithoutBlockingLaterFrames() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let frames = (1...9).map { "{\"jsonrpc\":\"2.0\",\"id\":\($0),\"method\":\"tools/list\"}\n" }.joined()
        try input.fileHandleForWriting.write(contentsOf: Data(frames.utf8))
        var iterator = await transport.receive().makeAsyncIterator()
        for _ in 0..<8 { let frame = try await iterator.next(); XCTAssertNotNil(frame) }
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&descriptor, 1, 1_000), 1)
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
        let overload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes.prefix(max(0, count)))) as? [String: Any])
        XCTAssertEqual(overload["id"] as? Int, 9)
        XCTAssertNotNil(overload["error"])
        let existing = await transport.requestTicket(id: .number(1))
        let ticket = try XCTUnwrap(existing)
        try await transport.send(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}".utf8))
        await transport.retire(id: .number(1), ticket: ticket)
        try input.fileHandleForWriting.write(contentsOf: Data("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"ping\"}\n".utf8))
        let tenth = try await iterator.next()
        XCTAssertTrue(String(decoding: try XCTUnwrap(tenth), as: UTF8.self).contains("\"id\":10"))
        await transport.disconnect()
    }

    func testNullAndMalformedRequestIDsCannotBypassCredits() async throws {
        for id in ["null", "true", "{}", "[]", "1.5"] {
            let input = Pipe(), output = Pipe()
            let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                                 output: output.fileHandleForWriting.fileDescriptor)
            try await transport.connect()
            let frame = "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"tools/list\",\"params\":{}}\n"
            try input.fileHandleForWriting.write(contentsOf: Data(String(repeating: frame, count: 9).utf8))
            let stream = await transport.receive()
            var count = 0
            do { for try await _ in stream { count += 1 }; XCTFail("Invalid ID admitted") } catch {}
            XCTAssertEqual(count, 0)
            await transport.disconnect()
        }
    }

    func testOldDispatchTicketCannotRetireReusedID() async throws {
        let input = Pipe(), output = Pipe()
        let transport = BoundedStdioTransport(input: input.fileHandleForReading.fileDescriptor,
                                             output: output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        var iterator = await transport.receive().makeAsyncIterator()
        let data = Data("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}\n".utf8)
        try input.fileHandleForWriting.write(contentsOf: data)
        _ = try await iterator.next()
        let first = await transport.requestTicket(id: .number(7))
        let firstTicket = try XCTUnwrap(first)
        await transport.retire(id: .number(7), ticket: firstTicket)
        try input.fileHandleForWriting.write(contentsOf: data)
        _ = try await iterator.next()
        let second = await transport.requestTicket(id: .number(7))
        XCTAssertNotEqual(first, second)
        await transport.retire(id: .number(7), ticket: firstTicket)
        let retained = await transport.requestTicket(id: .number(7))
        XCTAssertEqual(retained, second)
        await transport.disconnect()
    }

    func testCancellationTargetRejectsMalformedIDs() throws {
        for id in ["null", "true", "{}", "[]", "1.5"] {
            let data = Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":\(id)}}".utf8)
            XCTAssertThrowsError(try FiniteMCPServer.cancellationTarget(data))
        }
        let integer = Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":7}}".utf8)
        XCTAssertEqual(try FiniteMCPServer.cancellationTarget(integer), .number(7))
        let string = Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":\"literal\"}}".utf8)
        XCTAssertEqual(try FiniteMCPServer.cancellationTarget(string), .string("literal"))
    }
}
