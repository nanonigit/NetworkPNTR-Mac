import Foundation
import Network
import Security
import XCTest
@testable import ArtexCore

final class CloudEgressPolicyTests: XCTestCase {
    func testOnlyFixedProviderOperationsCanGenerateRequests() throws {
        let expected: [CloudEgressRoute: (String, String, String)] = [
            .openAIModels: ("api.openai.com", "GET", "/v1/models"),
            .openAIChat: ("api.openai.com", "POST", "/v1/chat/completions"),
            .openAIResponses: ("api.openai.com", "POST", "/v1/responses"),
            .anthropicModels: ("api.anthropic.com", "GET", "/v1/models"),
            .anthropicMessages: ("api.anthropic.com", "POST", "/v1/messages"),
            .geminiModels: ("generativelanguage.googleapis.com", "GET", "/v1beta/openai/models"),
            .geminiChat: ("generativelanguage.googleapis.com", "POST", "/v1beta/openai/chat/completions"),
            .groqModels: ("api.groq.com", "GET", "/openai/v1/models"),
            .groqChat: ("api.groq.com", "POST", "/openai/v1/chat/completions")
        ]
        XCTAssertEqual(Set(CloudEgressRoute.allCases), Set(expected.keys))
        for (route, (host, method, path)) in expected {
            let isPOST = method == "POST"
            let body = isPOST ? Data("{\"model\":\"fixture\"}".utf8) : Data()
            let request = try CloudEgressRequest(route: route, apiKey: "fixture-key", body: body, streaming: isPOST)
            let head = String(decoding: request.header, as: UTF8.self)
            XCTAssertTrue(head.hasPrefix("\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\n"))
            XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
            XCTAssertTrue(head.contains("Connection: close\r\n"))
            XCTAssertTrue(head.contains("Accept-Encoding: identity\r\n"))
            XCTAssertEqual(request.body, body)
            if host == "api.anthropic.com" {
                XCTAssertTrue(head.contains("x-api-key: fixture-key\r\nanthropic-version: 2023-06-01\r\n"))
                XCTAssertFalse(head.contains("Authorization:"))
            } else {
                XCTAssertTrue(head.contains("Authorization: Bearer fixture-key\r\n"))
                XCTAssertFalse(head.contains("x-api-key:"))
            }
            if isPOST {
                XCTAssertTrue(head.contains("Content-Length: \(body.count)\r\n"))
                XCTAssertTrue(head.contains("Accept: text/event-stream\r\n"))
            } else {
                XCTAssertFalse(head.contains("Content-Length:"))
                XCTAssertTrue(head.contains("Accept: application/json\r\n"))
            }
        }
        for invalid in ["https://api.openai.com/v1/models", "openai.models\r\nHost: example.invalid", "gemini.responses", "groq.models?x=y"] {
            XCTAssertNil(CloudEgressRoute(rawValue: invalid))
        }
    }

    func testUntrustedKeyAndBodyCannotAlterFraming() throws {
        for key in ["", "a b", "a\r\nHost:bad", "a\u{0}", "秘密", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try CloudEgressRequest(route: .groqModels, apiKey: key))
        }
        XCTAssertThrowsError(try CloudEgressRequest(route: .groqModels, apiKey: "key", body: Data([0])))
        XCTAssertThrowsError(try CloudEgressRequest(route: .groqModels, apiKey: "key", streaming: true))
        XCTAssertThrowsError(try CloudEgressRequest(route: .groqChat, apiKey: "key"))
        XCTAssertThrowsError(try CloudEgressRequest(route: .groqChat, apiKey: "key", body: Data(count: CloudEgressRequest.maximumBodyBytes + 1)))
        let request = try CloudEgressRequest(route: .groqChat, apiKey: "do-not-print", body: Data("private-prompt".utf8))
        for output in [String(describing: request), String(reflecting: request)] {
            XCTAssertFalse(output.contains("do-not-print"))
            XCTAssertFalse(output.contains("private-prompt"))
        }
    }

    func testResolverResultPinsNumericIPAndFixedTLSAuthority() throws {
        let v4 = NWEndpoint.Host.ipv4(try XCTUnwrap(IPv4Address("8.8.8.8")))
        let v6 = NWEndpoint.Host.ipv6(try XCTUnwrap(IPv6Address("2606:4700::1111")))
        let destinations = try CloudEgressRoute.geminiChat.destinations { absoluteName in
            XCTAssertEqual(absoluteName, "generativelanguage.googleapis.com.")
            return [v6, v4, v6]
        }
        XCTAssertEqual(destinations.map(\.endpoint), [.hostPort(host: v6, port: .https), .hostPort(host: v4, port: .https)])
        XCTAssertTrue(destinations.allSatisfy { $0.hostname == "generativelanguage.googleapis.com" })
    }

    func testEverySpecialAnswerPoisonsMixedResultsBeforeConnection() throws {
        let v4 = try XCTUnwrap(IPv4Address("8.8.8.8"))
        let specialV4 = ["0.1.2.3", "10.0.0.1", "100.64.0.0", "100.127.255.255", "127.0.0.1",
                         "169.254.169.254", "172.16.0.0", "172.31.255.255", "192.0.0.9", "192.0.2.1",
                         "192.31.196.1", "192.52.193.1", "192.88.99.1", "192.168.1.1", "192.175.48.1",
                         "198.18.0.1", "198.19.255.255", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255"]
        let specialV6 = ["::", "::1", "::ffff:8.8.8.8", "64:ff9b::0808:0808", "100::1", "2001:1::1", "2001:1ff::1",
                         "2001:db8::1", "2002:0808:0808::1", "2620:4f:8000::1", "3fff:fff::1", "5f00::1",
                         "fc00::1", "fd00::1", "fe80::1", "ff02::1"]
        let denied = try specialV4.map { NWEndpoint.Host.ipv4(try XCTUnwrap(IPv4Address($0))) }
            + specialV6.map { NWEndpoint.Host.ipv6(try XCTUnwrap(IPv6Address($0))) }
            + [.name("api.groq.com", nil)]
        for host in denied {
            XCTAssertThrowsError(try CloudEgressRoute.groqChat.destinations { _ in [.ipv4(v4), host] }, "\(host)")
        }
        XCTAssertThrowsError(try CloudEgressRoute.groqChat.destinations { _ in [] })
        XCTAssertThrowsError(try CloudEgressRoute.groqChat.destinations { _ in Array(repeating: .ipv4(v4), count: 33) })
    }

    func testTLSVerifiesFixedHostnameAndRejectsUntrustedChain() throws {
        func certificate(_ name: String) throws -> SecCertificate {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "der", subdirectory: "Fixtures/cloud-egress"))
            return try XCTUnwrap(SecCertificateCreateWithData(nil, Data(contentsOf: url) as CFData))
        }
        let leaf = try certificate("openai-leaf")
        let root = try certificate("root")
        func trust(anchored: Bool) throws -> SecTrust {
            var candidate: SecTrust?
            XCTAssertEqual(SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &candidate), errSecSuccess)
            let trust = try XCTUnwrap(candidate)
            XCTAssertEqual(SecTrustSetVerifyDate(trust, Date(timeIntervalSince1970: 1_794_009_600) as CFDate), errSecSuccess)
            if anchored {
                XCTAssertEqual(SecTrustSetAnchorCertificates(trust, [root] as CFArray), errSecSuccess)
                XCTAssertEqual(SecTrustSetAnchorCertificatesOnly(trust, true), errSecSuccess)
            }
            return trust
        }

        let ip = try XCTUnwrap(IPv4Address("8.8.8.8"))
        let matching = try XCTUnwrap(CloudEgressRoute.openAIChat.destinations { _ in [.ipv4(ip)] }.first)
        let wrongName = try XCTUnwrap(CloudEgressRoute.groqChat.destinations { _ in [.ipv4(ip)] }.first)
        XCTAssertTrue(matching.verifiesTLS(try trust(anchored: true)))
        XCTAssertFalse(wrongName.verifiesTLS(try trust(anchored: true)))
        XCTAssertFalse(matching.verifiesTLS(try trust(anchored: false)))
    }
}
