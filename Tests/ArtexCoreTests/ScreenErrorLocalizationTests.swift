import XCTest
@testable import ArtexCore

@MainActor private final class LanguageTestVault: SessionVault {
    var removes = 0
    func load() throws -> String? { nil }
    func save(_ token: String) throws { XCTFail("Validation must not save a session") }
    func remove() throws { removes += 1 }
}

final class ScreenErrorLocalizationTests: XCTestCase {
    @MainActor func testAuthenticationValidationKeepsPhaseAndAvoidsSideEffectsWhileResolvingLanguage() async throws {
        let api = ChatTestTransport(); let vault = LanguageTestVault()
        let session = AuthenticationSession(client: api,vault:vault,setupToken:"fixture")
        try api.enqueue(["initialized":false,"setup_token_required":true]); await session.refresh()
        await session.setup(password:"short",confirmation:"different")
        let failure = try XCTUnwrap(session.failure); let count = api.calls.count
        XCTAssertEqual(failure.text(language:.english),"The passwords do not match.")
        XCTAssertEqual(failure.text(language:.japanese),session.error)
        XCTAssertEqual(session.phase,.needsSetup); XCTAssertFalse(session.isBusy)
        XCTAssertEqual(api.calls.count,count); XCTAssertEqual(vault.removes,1)
        await session.setup(password:"short",confirmation:"short")
        XCTAssertEqual(session.failure?.text(language:.english),"Enter a password with at least 8 characters.")
        XCTAssertEqual(api.calls.count,count)
    }
    @MainActor func testUnknownAuthenticationFailureDoesNotRetainPrivateDescription() async {
        let api = ChatTestTransport(); api.handler = { _ in throw NSError(domain:"private",code:1,userInfo:[NSLocalizedDescriptionKey:"private-secret /Users/private"]) }
        let session = AuthenticationSession(client:api,vault:LanguageTestVault(),setupToken:"fixture")
        await session.refresh()
        XCTAssertEqual(session.phase,.unavailable)
        XCTAssertEqual(session.failure?.text(language:.english),"Check communication with the runtime.")
        XCTAssertEqual(session.error,"実行環境との通信を確認してください。")
    }
    @MainActor func testConfirmedLLMSaveKeepsLocalizedNoticeWhenRefreshFailsWithoutResaving() async throws {
        let api = ChatTestTransport(); let store = LLMStore(service:LLMService(client:api))
        var draft = LLMProfileDraft();draft.name="literal 中文 한국어";draft.model="fixture"
        try api.enqueue(["id":7]);try api.enqueue(["error":"private-secret"],status:503)
        let saved = await store.save(draft);XCTAssertTrue(saved)
        let calls = api.calls.count
        XCTAssertEqual(store.noticeKey,.llmNoticeSaved)
        XCTAssertEqual(AppStrings.text(try XCTUnwrap(store.noticeKey),language:.english),"Model configuration saved.")
        XCTAssertEqual(store.notice,"モデル設定を保存しました。")
        XCTAssertEqual(store.failure?.text(language:.english),"The database is unavailable. Try again after recovery.")
        XCTAssertEqual(api.calls.count,calls);XCTAssertEqual(api.calls.filter{$0.method=="POST"}.count,1)
        XCTAssertEqual(draft.name,"literal 中文 한국어");XCTAssertFalse(store.isMutating)
    }
    @MainActor func testDashboardCachedTasksAndTimestampSurviveFailedRefreshAndLanguageResolution() async throws {
        let api = ChatTestTransport();let store = DashboardStore(service:DashboardService(client:api))
        try api.enqueue(["tasks":[]]);await store.refreshTasks()
        let date = try XCTUnwrap(store.tasks.updatedAt)
        try api.enqueue(["error":"private-secret"],status:429);await store.refreshTasks()
        let calls = api.calls.count
        XCTAssertEqual(store.tasks.failure?.text(language:.english),"Too many attempts. Wait a while and try again.")
        XCTAssertEqual(store.tasks.failure?.text(language:.japanese),store.tasks.error)
        XCTAssertEqual(store.tasks.value?.count,0);XCTAssertEqual(store.tasks.updatedAt,date)
        XCTAssertEqual(api.calls.count,calls);XCTAssertFalse(store.tasks.isLoading)
    }
}
