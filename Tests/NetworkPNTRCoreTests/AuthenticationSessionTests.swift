import XCTest
@testable import NetworkPNTRCore

@MainActor private final class FixtureVault: SessionVault {
    var value: String?
    var fails = false
    func load() throws -> String? { if fails { throw BackendAPIError.secureStorage(-1) }; return value }
    func save(_ token: String) throws { if fails { throw BackendAPIError.secureStorage(-1) }; value = token }
    func remove() throws { if fails { throw BackendAPIError.secureStorage(-1) }; value = nil }
}
@MainActor private final class FixtureAPI: BackendJSONTransport {
    var replies: [BackendHTTPResponse] = []
    var paths: [String] = []
    var bodies: [Data?] = []
    func enqueue(_ status: Int, _ object: [String: Any]) throws { replies.append(BackendHTTPResponse(status: status, body: try JSONSerialization.data(withJSONObject: object))) }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path); bodies.append(body)
        guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }
        return replies.removeFirst()
    }
}
final class AuthenticationSessionTests: XCTestCase {
    @MainActor func testUnavailableStatusNeverOpensSetupOrDeletesSavedToken() async throws {
        let api = FixtureAPI(); try api.enqueue(503, [:])
        let vault = FixtureVault(); vault.value = "existing.jwt"
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture-setup")
        await session.refresh()
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertEqual(vault.value, "existing.jwt")
        XCTAssertNotNil(session.error)
    }
    @MainActor func testProtectedEndpointFailurePreservesSavedSession() async throws {
        let api = FixtureAPI(); try api.enqueue(200, ["initialized": true, "setup_token_required": false]); try api.enqueue(503, [:])
        let vault = FixtureVault(); vault.value = "existing.jwt"
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture-setup")
        await session.refresh()
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertEqual(vault.value, "existing.jwt")
    }
    @MainActor func testSetupValidatesBeforeNetworkAndPersistsOnlySession() async throws {
        let api = FixtureAPI(); try api.enqueue(200, ["initialized": false, "setup_token_required": true])
        let vault = FixtureVault()
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture-setup")
        await session.refresh()
        XCTAssertEqual(session.phase, .needsSetup)
        for (password, confirmation) in [("short", "short"), ("correctlength", "mismatch"), (String(repeating: "あ", count: 25), String(repeating: "あ", count: 25))] {
            await session.setup(password: password, confirmation: confirmation)
            XCTAssertNotNil(session.error)
        }
        XCTAssertEqual(api.paths.count, 1)
        try api.enqueue(200, ["token": "fixture.jwt"])
        await session.setup(password: "password-fixture", confirmation: "password-fixture")
        XCTAssertEqual(session.phase, .authenticated)
        XCTAssertEqual(vault.value, "fixture.jwt")
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(api.bodies.last!)) as? [String: String]
        XCTAssertEqual(sent?["setup_token"], "fixture-setup")
        session.logout()
        XCTAssertNil(vault.value)
        XCTAssertEqual(session.phase, .needsLogin)
    }
    @MainActor func testLoginRequiresAgreementAndHandlesRejectionAndKeychainFailure() async throws {
        let api = FixtureAPI(); try api.enqueue(200, ["initialized": true, "setup_token_required": false])
        let vault = FixtureVault()
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture-setup")
        await session.refresh()
        await session.login(password: "password-fixture", agreed: false)
        XCTAssertEqual(api.paths.count, 1)
        try api.enqueue(401, ["error": "credential"])
        await session.login(password: "wrong", agreed: true)
        XCTAssertEqual(session.phase, .needsLogin)
        XCTAssertNil(vault.value)
        try api.enqueue(200, ["token": "fixture.jwt"])
        vault.fails = true
        await session.login(password: "password-fixture", agreed: true)
        XCTAssertNotEqual(session.phase, .authenticated)
        XCTAssertNotNil(session.error)
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(api.bodies.last!)) as? [String: String]
        XCTAssertEqual(sent?["username"], "ARTEX")
    }
    @MainActor func testSavedSessionMustPassProtectedEndpointAndInvalidTokenIsRemoved() async throws {
        let api = FixtureAPI(); let vault = FixtureVault(); vault.value = "old.jwt"
        try api.enqueue(200, ["initialized": true, "setup_token_required": false]); try api.enqueue(401, [:])
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture-setup")
        await session.refresh()
        XCTAssertEqual(session.phase, .needsLogin)
        XCTAssertNil(vault.value)
        vault.value = "valid.jwt"
        try api.enqueue(200, ["initialized": true, "setup_token_required": false]); try api.enqueue(200, ["profiles": []])
        await session.refresh()
        XCTAssertEqual(session.phase, .authenticated)
        XCTAssertEqual(api.paths.last, "/api/llm/profiles")
    }
}
