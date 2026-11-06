import Foundation
import XCTest
@testable import ArtexCore

final class CloudEgressResponseTests: XCTestCase {
    private let chunked = Data((
        "HTTP/1.1 103 Early Hints\r\nLink: ignored\r\n\r\n" +
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: Chunked\r\nContent-Type: text/event-stream; charset=utf-8\r\n" +
        "Set-Cookie: ignored\r\n\r\n3 ; x = \"quoted\\\";value\";flag\r\nabc\r\n2\r\nde\r\n0\r\nX-Trailer: ignored\r\n\r\n"
    ).utf8)

    func testChunkedResponseAtEverySplitAndOneByteAtATime() throws {
        for split in 0...chunked.count {
            try assertStream([Data(chunked.prefix(split)), Data(chunked.dropFirst(split))])
        }
        try assertStream(chunked.map { Data([$0]) })
    }

    func testTruncationAndTransportFailureNeverEmitEnd() throws {
        for prefix in 0..<chunked.count {
            var events: [CloudEgressResponseEvent] = []
            XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { events.append($0) }) { consume in
                try consume(Data(chunked.prefix(prefix)))
            })
            XCTAssertFalse(events.contains(.end))
        }
        var events: [CloudEgressResponseEvent] = []
        XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { events.append($0) }) { consume in
            try consume(chunked)
            throw CancellationError()
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(events.contains(.end))
        XCTAssertTrue(events.contains(.body(Data("abc".utf8))))
    }

    func testLengthCloseAndBodylessResponses() throws {
        let cases: [(String, [CloudEgressResponseEvent])] = [
            ("HTTP/1.1 429 Limited\r\nContent-Length: 3\r\nContent-Type: application/json\r\n\r\nabc",
             [.head(status: 429, type: .json), .body(Data("abc".utf8)), .end]),
            ("HTTP/1.0 200 OK\r\n\r\nabc", [.head(status: 200, type: nil), .body(Data("abc".utf8)), .end]),
            ("HTTP/1.1 204 No Content\r\n\r\n", [.head(status: 204, type: nil), .end])
        ]
        for (response, expected) in cases {
            var events: [CloudEgressResponseEvent] = []
            try CloudEgressTransport.frameResponse(receive: { events.append($0) }) { try $0(Data(response.utf8)) }
            XCTAssertEqual(events, expected)
        }
    }

    func testMalformedOrRedirectResponsesFailWithoutCompletion() {
        let malformed = [
            "HTTP/1.1 307 Redirect\r\nLocation: https://other.invalid/token\r\n\r\nsecret",
            "HTTP/1.1 101 Switching Protocols\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\ncontent-length: 1\r\n\r\na",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunKed\r\n\r\n0\r\n\r\n",
            "HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n",
            "HTTP/1.1 200 OK\r\nX: a\n b\r\n\r\n",
            "HTTP/1.1 200 OK\r\n X: a\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nab",
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nax",
            "HTTP/1.1 204 No Content\r\n\r\nx",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\naXX0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1;=\r\na\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1;x=\"unclosed\r\na\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 2\r\n\r\n"
        ]
        for (index, input) in malformed.enumerated() {
            var events: [CloudEgressResponseEvent] = []
            XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { events.append($0) }) { try $0(Data(input.utf8)) }, "case \(index)")
            XCTAssertFalse(events.contains(.end), "case \(index)")
            if index == 0 { XCTAssertTrue(events.isEmpty) }
        }
    }

    func testLimitsAndSinkFailure() {
        for wire in [
            "HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: 32768) + "\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1;" + String(repeating: "a", count: 1024) + "\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX: " + String(repeating: "a", count: 8192) + "\r\n\r\n",
            String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 5),
            "HTTP/1.1 200 OK\r\nContent-Length: 16777217\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1000001\r\n"
        ] {
            XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { _ in }) { try $0(Data(wire.utf8)) })
        }
        enum SinkFailure: Error { case closed }
        XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { event in
            if case .body = event { throw SinkFailure.closed }
            XCTAssertNotEqual(event, .end)
        }) { try $0(chunked) }) { XCTAssertTrue($0 is SinkFailure) }
    }

    func testCloseDelimitedBodyCannotExceedCumulativeLimit() {
        var received = 0
        let part = Data(repeating: 0xAB, count: 65536)
        XCTAssertThrowsError(try CloudEgressTransport.frameResponse(receive: { event in
            if case .body(let data) = event { received += data.count }
            XCTAssertNotEqual(event, .end)
        }) { consume in
            try consume(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
            for _ in 0..<256 { try consume(part) }
            try consume(Data([0xAB]))
        }) { XCTAssertEqual($0 as? CloudEgressResponseError, .limit) }
        XCTAssertEqual(received, 16 * 1024 * 1024)
    }

    private func assertStream(_ parts: [Data], file: StaticString = #filePath, line: UInt = #line) throws {
        var events: [CloudEgressResponseEvent] = []
        try CloudEgressTransport.frameResponse(receive: { events.append($0) }) { consume in
            for part in parts { try consume(part) }
            XCTAssertFalse(events.contains(.end), file: file, line: line)
        }
        XCTAssertEqual(events.first, .head(status: 200, type: .eventStream), file: file, line: line)
        XCTAssertEqual(events.last, .end, file: file, line: line)
        let body = events.reduce(into: Data()) { result, event in
            if case .body(let bytes) = event { result.append(bytes) }
        }
        XCTAssertEqual(body, Data("abcde".utf8), file: file, line: line)
    }
}
