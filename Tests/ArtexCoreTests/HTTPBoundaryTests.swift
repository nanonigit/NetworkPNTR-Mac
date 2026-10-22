import XCTest
@testable import ArtexCore

final class HTTPBoundaryTests: XCTestCase {
    func testContentLengthAndChunkedResponses() throws {
        let plain = try BackendHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8))
        XCTAssertEqual(plain.status, 200)
        XCTAssertEqual(plain.body, Data("{}".utf8))
        let chunked = try BackendHTTPResponse.parse(Data("HTTP/1.1 401 Unauthorized\r\nTransfer-Encoding: chunked\r\n\r\n1;test=yes\r\n{\r\n1\r\n}\r\n0\r\nX-Test: yes\r\n\r\n".utf8))
        XCTAssertEqual(chunked.status, 401)
        XCTAssertEqual(chunked.body, plain.body)
    }
    func testMalformedTruncatedAndAmbiguousResponsesAreRejected() {
        for wire in ["HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n{}", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n{}", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nF\r\n{}\r\n0\r\n\r\n", "HTTP/1.1 200 OK\n\n{}"] {
            XCTAssertThrowsError(try BackendHTTPResponse.parse(Data(wire.utf8)))
        }
    }
    func testRequestCannotInjectHeadersOrChangeDestination() throws {
        let request = try BackendHTTPRequest.make(method: "GET", path: "/api/auth/status", body: nil, bearer: nil)
        XCTAssertTrue(String(decoding: request, as: UTF8.self).contains("Host: localhost\r\n"))
        for path in ["https://example.com/", "/api/tasks\r\nInjected: yes", "/api/a b"] {
            XCTAssertThrowsError(try BackendHTTPRequest.make(method: "GET", path: path, body: nil, bearer: nil))
        }
        XCTAssertThrowsError(try BackendHTTPRequest.make(method: "GET", path: "/api/auth/status", body: nil, bearer: "bad\r\nInjected: yes"))
    }
}
