import Foundation
import XCTest
@testable import ArtexCore

@MainActor private final class LanguageVault: SessionVault {
    func load() throws -> String? { "fixture-session" }
    func save(_ token: String) throws {}
    func remove() throws {}
}

@MainActor private final class LanguageBackend: BackendJSONTransport {
    var methods: [String] = []
    var writes: [String] = []
    var output = "ko"
    var readGate: CheckedContinuation<Void, Never>?
    var writeGate: CheckedContinuation<Void, Never>?
    var holdRead = false
    var holdWrite = false
    var wrongReceipt = false

    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        if path == "/api/auth/status" {
            return try ChatTestTransport.response(["initialized": true, "setup_token_required": false])
        }
        guard bearer == "fixture-session" else { throw BackendAPIError.status(401) }
        if path == "/api/llm/profiles" { return try ChatTestTransport.response(["profiles": []]) }
        XCTAssertEqual(path, "/api/settings")
        methods.append(method)
        if method == "PUT" {
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: String])
            XCTAssertEqual(Set(sent.keys), ["output_language"])
            let language = try XCTUnwrap(sent["output_language"])
            writes.append(language)
            if holdWrite {
                holdWrite = false
                await withCheckedContinuation { writeGate = $0 }
            }
            output = language
            if wrongReceipt { return try ChatTestTransport.response(["output_language": "ko"]) }
        } else if holdRead {
            holdRead = false
            await withCheckedContinuation { readGate = $0 }
        }
        return try ChatTestTransport.response(["output_language": output, "traffic_capture": true])
    }
}

final class GuestOutputLanguageSyncTests: XCTestCase {
    @MainActor private func fixture() async -> (LanguageBackend, AuthenticationSession, GuestOutputLanguageSync) {
        let backend = LanguageBackend()
        let session = AuthenticationSession(client: backend, vault: LanguageVault(), setupToken: "")
        await session.refresh()
        XCTAssertEqual(session.phase, .authenticated)
        return (backend, session, GuestOutputLanguageSync())
    }

    @MainActor private func waitForGate(_ ready: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if ready() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Expected a held backend request")
        return false
    }

    @MainActor func testOnlySelectedValueIsWrittenAndMatchingValueIsNoOp() async {
        let (api, session, sync) = await fixture()
        await sync.update(.english, session: session)?.value
        await sync.update(.japanese, session: session)?.value
        await sync.update(.japanese, session: session)?.value
        XCTAssertEqual(api.methods, ["GET", "PUT", "GET", "PUT", "GET"])
        XCTAssertEqual(api.writes, ["en", "ja"])
        XCTAssertNil(sync.update(.english, session: nil))
    }

    @MainActor func testRemovalDuringReadPreventsWriteEvenWhenOldSessionStillAuthenticated() async {
        let (api, session, sync) = await fixture()
        api.holdRead = true
        let task = sync.update(.english, session: session)
        guard await waitForGate({ api.readGate != nil }) else { return }
        sync.update(.english, session: nil)
        api.readGate?.resume()
        await task?.value
        XCTAssertTrue(api.writes.isEmpty)
    }

    @MainActor func testLatestSelectionWaitsForDispatchedWriteAndSupersedesPendingSelections() async {
        let (api, session, sync) = await fixture()
        api.holdWrite = true
        let task = sync.update(.english, session: session)
        guard await waitForGate({ api.writeGate != nil }) else { return }
        sync.update(.japanese, session: session)
        sync.update(.english, session: session)
        sync.update(.japanese, session: session)
        XCTAssertEqual(api.writes, ["en"])
        api.writeGate?.resume()
        await task?.value
        XCTAssertEqual(api.writes, ["en", "ja"])
        XCTAssertEqual(api.output, "ja")
    }

    @MainActor func testLogoutDuringReadDoesNotDispatchAndBadReceiptDoesNotReplay() async {
        let (api, session, sync) = await fixture()
        api.holdRead = true
        let task = sync.update(.english, session: session)
        guard await waitForGate({ api.readGate != nil }) else { return }
        session.logout()
        api.readGate?.resume()
        await task?.value
        XCTAssertTrue(api.writes.isEmpty)
        await session.refresh()
        api.wrongReceipt = true
        await sync.update(.english, session: session)?.value
        XCTAssertEqual(api.writes, ["en"])
    }
}
