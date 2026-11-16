import Foundation
import Synchronization
import XCTest
@testable import ArtexCore

private final class OllamaFixtureProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        let path: String
        let status: Int
        let body: Data
        var headers: [String: String] = [:]
        var hold = false
        var redirect = false
    }
    struct State: Sendable {
        let generation = UUID()
        var responses: [Response] = []
        var paths: [String] = []
        var stops = 0
    }
    static let state = Mutex(State())
    private var generation: UUID?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let next = Self.state.withLock { state -> Response? in
            generation = state.generation
            state.paths.append(request.url?.path ?? "")
            return state.responses.isEmpty ? nil : state.responses.removeFirst()
        }
        guard let next, request.url?.path == next.path,
              request.url?.host == "127.0.0.1", request.url?.port == 11434 else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        if next.hold { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: next.headers)!
        if next.redirect {
            let destination = URLRequest(url: URL(string: "https://example.invalid/redirected")!)
            client?.urlProtocol(self, wasRedirectedTo: destination, redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.state.withLock {
            if $0.generation == generation { $0.stops += 1 }
        }
    }
}

final class OllamaCatalogTests: XCTestCase {
    #if DEBUG
    func testGuestFixturePreservesStreamAndRequiresPinnedModelAndLoadedContext() async throws {
        let runtime = OllamaCatalog(protocolClasses: [OllamaFixtureProtocol.self])
        func json(_ path: String, _ body: String) -> OllamaFixtureProtocol.Response {
            .init(path: path, status: 200, body: Data(body.utf8))
        }
        let body = Data(#"{"model":"fixture","messages":[{"role":"user","content":"synthetic"}],"stream":true}"#.utf8)
        let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n"
        let responses = [
            json("/api/tags", #"{"models":[{"name":"fixture"}]}"#),
            json("/api/show", #"{"model_info":{"general.architecture":"fixture","fixture.context_length":16384}}"#),
            json("/api/status", #"{"cloud":{"disabled":true}}"#),
            json("/v1/chat/completions", stream),
            json("/api/ps", #"{"models":[{"name":"fixture","context_length":8192}]}"#)
        ]
        OllamaFixtureProtocol.state.withLock { $0 = .init(responses: responses) }
        let events = Mutex<[CloudEgressResponseEvent]>([])
        try await runtime.exchangeGuestFixture(model: "fixture", body: body) { event in
            events.withLock { $0.append(event) }
        }
        let received = events.withLock { $0 }
        XCTAssertEqual(received.first, .head(status: 200, type: .eventStream))
        XCTAssertEqual(received.last, .end)
        let chunks = received.compactMap { event -> Data? in
            if case .body(let data) = event { return data }
            return nil
        }
        XCTAssertEqual(chunks.reduce(into: Data()) { $0.append($1) }, Data(stream.utf8))
        OllamaFixtureProtocol.state.withLock { $0 = .init() }
        do {
            try await runtime.exchangeGuestFixture(model: "other", body: body) { _ in }
            XCTFail("Unselected model accepted")
        } catch OllamaCatalog.Failure.invalidChatRequest {}
        XCTAssertTrue(OllamaFixtureProtocol.state.withLock { $0.paths.isEmpty })

        var wrongContext = responses
        wrongContext[4] = json("/api/ps", #"{"models":[{"name":"fixture","context_length":4096}]}"#)
        OllamaFixtureProtocol.state.withLock { $0 = .init(responses: wrongContext) }
        let ended = Mutex(false)
        do {
            try await runtime.exchangeGuestFixture(model: "fixture", body: body) { event in
                if event == .end { ended.withLock { $0 = true } }
            }
            XCTFail("Unverified loaded context accepted")
        } catch OllamaCatalog.Failure.unverifiedContextLength {}
        XCTAssertFalse(ended.withLock { $0 })
    }
    #endif

    func testLocalBoundaryRejectsCloudStatusRedirectAndOversizedResponses() async throws {
        let runtime = OllamaCatalog(protocolClasses: [OllamaFixtureProtocol.self])
        func configure(_ responses: [OllamaFixtureProtocol.Response]) {
            OllamaFixtureProtocol.state.withLock { $0 = .init(responses: responses) }
        }
        func json(_ path: String, _ body: String) -> OllamaFixtureProtocol.Response {
            .init(path: path, status: 200, body: Data(body.utf8))
        }
        configure([])
        do {
            _ = try await runtime.installed()
            XCTFail("Unavailable runtime succeeded")
        } catch {}

        configure([json("/api/tags", #"{"models":[{"name":"fixture"}]}"#),
                   json("/api/show", #"{"model_info":{"general.architecture":"fixture","fixture.context_length":4096}}"#),
                   json("/api/status", #"{"cloud":{"disabled":false}}"#)])
        do {
            _ = try await runtime.chat(model: "fixture", messages: [.init(role: .user, content: "synthetic fixture")])
            XCTFail("Cloud-enabled runtime accepted conversation")
        } catch OllamaCatalog.Failure.cloudEnabled {}
        XCTAssertEqual(OllamaFixtureProtocol.state.withLock { $0.paths }, ["/api/tags", "/api/show", "/api/status"])

        configure([.init(path: "/api/tags", status: 307, body: Data(), headers: ["Location": "https://example.invalid/redirected"], redirect: true)])
        do {
            _ = try await runtime.installed()
            XCTFail("Redirect accepted")
        } catch OllamaCatalog.Failure.status(307) {}
        XCTAssertEqual(OllamaFixtureProtocol.state.withLock { $0.paths }, ["/api/tags"])

        configure([.init(path: "/api/tags", status: 200, body: Data(), headers: ["Content-Length": "4194305"])])
        do {
            _ = try await runtime.installed()
            XCTFail("Oversized response accepted")
        } catch OllamaCatalog.Failure.oversizedResponse {}

        configure([.init(path: "/api/tags", status: 200, body: Data(repeating: 32, count: 4 * 1_024 * 1_024 + 1))])
        do {
            _ = try await runtime.installed()
            XCTFail("Unannounced oversized response accepted")
        } catch OllamaCatalog.Failure.oversizedResponse {}

        configure([])
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runtime.installed()
        }
        do {
            _ = try await canceled.value
            XCTFail("Canceled request succeeded")
        } catch is CancellationError {}
        XCTAssertTrue(OllamaFixtureProtocol.state.withLock { $0.paths.isEmpty })

        configure([.init(path: "/api/tags", status: 200, body: Data(), hold: true)])
        let pending = Task { try await runtime.installed() }
        defer { pending.cancel() }
        for _ in 0..<1_000 {
            if OllamaFixtureProtocol.state.withLock({ !$0.paths.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(OllamaFixtureProtocol.state.withLock { $0.paths }, ["/api/tags"])
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("In-flight cancellation succeeded")
        } catch {
            let canceled = error is CancellationError || (error as? URLError)?.code == .cancelled
            XCTAssertTrue(canceled)
        }
        XCTAssertGreaterThan(OllamaFixtureProtocol.state.withLock { $0.stops }, 0)
    }
}
