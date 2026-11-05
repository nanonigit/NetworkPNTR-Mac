import Network
import XCTest
@testable import ArtexCore

final class CloudEgressTransportTests: XCTestCase {
    func testMismatchedHostnameIsRejectedBeforeExchange() throws {
        let request = try CloudEgressRequest(route: .geminiModels, apiKey: "fixture")
        let ip = try XCTUnwrap(IPv4Address("8.8.8.8"))
        let wrongPeer = try XCTUnwrap(CloudEgressRoute.openAIModels.destinations { _ in [.ipv4(ip)] }.first)
        XCTAssertThrowsError(try CloudEgressTransport.exchange(request, at: wrongPeer, cancellation: CloudEgressCancellation()) { _ in
            XCTFail("no response may be delivered")
        }) { error in
            XCTAssertEqual(error as? CloudEgressTransportError, .mismatchedTarget)
        }
    }

    func testCancellationBeforeDialIsSticky() throws {
        let request = try CloudEgressRequest(route: .groqModels, apiKey: "fixture")
        let ip = try XCTUnwrap(IPv6Address("2606:4700::1111"))
        let peer = try XCTUnwrap(request.route.destinations { _ in [.ipv6(ip)] }.first)
        let cancellation = CloudEgressCancellation()
        cancellation.cancel()
        cancellation.cancel()
        XCTAssertThrowsError(try CloudEgressTransport.exchange(request, at: peer, cancellation: cancellation) { _ in
            XCTFail("no response may be delivered")
        }) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}
