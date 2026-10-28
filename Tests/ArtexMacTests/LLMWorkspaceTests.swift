import XCTest
import ArtexCore
@testable import ArtexMac

@MainActor private final class LLMWorkspaceBackend: BackendJSONTransport {
    var calls = 0
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        return .init(status: 503, body: Data("{}".utf8))
    }
}

final class LLMWorkspaceTests: XCTestCase {
    @MainActor func testSameOwnerNavigationRetainsUncertainStoreAndDoesNotRecreateIt() async throws {
        let workspace = LLMWorkspace(); let owner = NSObject(); let api = LLMWorkspaceBackend()
        let store = LLMStore(service: LLMService(client: api))
        workspace.attach(owner: owner) { store }
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        _ = await store.save(draft)
        let revision = try XCTUnwrap(store.unknownRevision)
        store.stop()
        var factories = 0
        workspace.attach(owner: owner) { factories += 1; return LLMStore(service: LLMService(client: api)) }
        XCTAssertEqual(factories, 0); XCTAssertTrue(workspace.store === store)
        store.resume(); _ = await store.save(draft)
        XCTAssertEqual(store.unknownRevision, revision); XCTAssertEqual(api.calls, 1)
    }
    @MainActor func testChangingAuthenticationOwnerStopsAndReplacesOldStore() {
        let workspace = LLMWorkspace(); let first = NSObject(), second = NSObject(); let api = LLMWorkspaceBackend()
        let old = LLMStore(service: LLMService(client: api)), replacement = LLMStore(service: LLMService(client: api))
        workspace.attach(owner: first) { old }
        workspace.attach(owner: second) { replacement }
        XCTAssertFalse(old.isActive); XCTAssertTrue(workspace.store === replacement)
        XCTAssertFalse(workspace.belongs(to: first)); XCTAssertTrue(workspace.belongs(to: second))
    }
    @MainActor func testAuthLossReleasesOwnerAndPrivateCachedState() {
        let workspace = LLMWorkspace(); let owner = NSObject(); let api = LLMWorkspaceBackend()
        let store = LLMStore(service: LLMService(client: api))
        workspace.attach(owner: owner) { store }; workspace.reset()
        XCTAssertFalse(store.isActive); XCTAssertNil(workspace.store); XCTAssertFalse(workspace.belongs(to: owner))
    }
}
