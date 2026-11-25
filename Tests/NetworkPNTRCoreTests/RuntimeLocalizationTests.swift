import XCTest
import Virtualization
@testable import NetworkPNTRCore

@MainActor private final class RuntimeLanguageVault: SessionVault {
    func load() throws -> String? { XCTFail("No auth before runtime validation");return nil }
    func save(_ token:String) throws { XCTFail("No auth before runtime validation") }
    func remove() throws { XCTFail("No auth before runtime validation") }
}
final class RuntimeLocalizationTests: XCTestCase {
    func testRuntimeCatalogAndParityFieldsResolveBothLanguages() throws {
        struct Fixture:Decodable {struct Entry:Decodable {let key:String;let en:String;let ja:String};let entries:[Entry]}
        let url = try XCTUnwrap(Bundle.module.url(forResource:"runtime-ui-localization",withExtension:"json",subdirectory:"Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url));XCTAssertEqual(fixture.entries.count,36)
        for entry in fixture.entries {
            let key = try XCTUnwrap(AppStringKey(rawValue:entry.key))
            XCTAssertEqual(AppStrings.text(key,language:.english),entry.en)
            XCTAssertEqual(AppStrings.text(key,language:.japanese),entry.ja)
        }
        let catalog = try FeatureCatalog.load()
        XCTAssertEqual(catalog.features.count,21);XCTAssertEqual(catalog.routes.count,27);XCTAssertEqual(catalog.endpoints.count,243)
        XCTAssertEqual(AppStrings.formatted(.runtimeUIParityWaiting,language:.english,values:["phase":"3"]),"Phase 3 · Awaiting migration")
    }
    func testLifecycleStatesAndRuntimeFailuresHideArbitraryDiagnosticText() {
        for (state,en,ja) in [(LifecycleState.idle,"Not started","未起動"),(.starting,"Starting","起動中"),(.running,"Running","実行中"),(.stopping,"Stopping","停止中"),(.stopped,"Stopped","停止済み"),(.failed,"Failed","失敗")] {
            XCTAssertEqual(RuntimeLabels.state(state,language:.english),en)
            XCTAssertEqual(RuntimeLabels.state(state,language:.japanese),ja)
        }
        for (error,key) in [(RuntimeError.invalidTransition("private-secret","private-secret"),AppStringKey.runtimeUITransitionError),(.integrity("private-secret /Users/private"),.runtimeUIIntegrityError),(.timeout("private-secret 中文 한국어"),.runtimeUITimeoutError),(.unsupported,.runtimeUIUnsupported)] {
            for language in AppLanguage.allCases {
                let expected = AppStrings.text(key,language:language)
                XCTAssertEqual(AppErrorText.text(error,language:language),expected)
                XCTAssertEqual(AppErrorMessage(error).text(language:language),expected)
                XCTAssertFalse(expected.contains("private-secret"))
            }
        }
        XCTAssertEqual(AppErrorMessage(NSError(domain:"private",code:1,userInfo:[NSLocalizedDescriptionKey:"private-secret"]),fallback:.runtimeUIUnexpected).text(language:.english),"The runtime operation failed. Check the guest log and try again.")
    }
    @MainActor func testLiveKernelFaultRemainsVisibleThroughLaterLogReadsAndClearsOnNewBoot() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for marker in ["Kernel panic - not syncing", "Internal error: Oops"] {
            let controller = VMController()
            controller.observeGuestLog("ARTEX_MAC_GUEST_READY")
            XCTAssertTrue(controller.guestReady)
            controller.observeGuestLog(marker + " private diagnostic")
            XCTAssertTrue(controller.hasGuestKernelFault)
            XCTAssertFalse(controller.guestReady)
            controller.observeGuestLog("ARTEX_MAC_GUEST_READY\nARTEX_MAC_GUEST_ERROR stage=fixture")
            XCTAssertFalse(controller.guestReady)
            for language in AppLanguage.allCases {
                let expected = AppStrings.text(.runtimeUIKernelFault, language: language)
                XCTAssertNotEqual(expected, AppStrings.text(.runtimeUIIntegrityError, language: language))
                XCTAssertEqual(AppErrorText.text(RuntimeError.guestKernelFault, language: language), expected)
                XCTAssertEqual(controller.failure?.text(language: language), expected)
                XCTAssertFalse(expected.contains("private diagnostic"))
            }
            do {
                try await controller.start(artifacts: missing, logs: missing)
                XCTFail("Missing artifacts accepted")
            } catch {}
            XCTAssertFalse(controller.hasGuestKernelFault)
        }
    }
    @MainActor func testDesktopPreflightFailureKeepsDiagnosticsAndSafeIdentityWithoutStartingVM() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture".utf8).write(to:file);defer {try? FileManager.default.removeItem(at:file)}
        let runtime = DesktopRuntime(artifacts:file,paths:.init(root:file),vault:RuntimeLanguageVault())
        await runtime.start()
        XCTAssertEqual(runtime.controller.state,.idle);XCTAssertFalse(runtime.controller.hasMachine)
        XCTAssertFalse(runtime.isStarting);XCTAssertNil(runtime.authentication)
        XCTAssertNotNil(runtime.error)
        XCTAssertEqual(runtime.failure?.text(language:.english),AppStrings.text(.runtimeUIIntegrityError,language:.english))
        XCTAssertEqual(runtime.failure?.text(language:.japanese),AppStrings.text(.runtimeUIIntegrityError,language:.japanese))
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.appendingPathComponent("state.ext4").path))
    }
    @MainActor func testControllerMissingArtifactFailureIsLocalizedBeforeAnyMachineIsCreated() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = VMController()
        do {try await controller.start(artifacts:missing,logs:missing);XCTFail("Missing artifacts accepted")} catch {}
        XCTAssertEqual(controller.state,.failed);XCTAssertFalse(controller.hasMachine);XCTAssertFalse(controller.guestReady)
        XCTAssertNotNil(controller.lastError)
        let key:AppStringKey = VZVirtualMachine.isSupported ? .runtimeUIUnexpected : .runtimeUIUnsupported
        XCTAssertEqual(controller.failure?.text(language:.english),AppStrings.text(key,language:.english))
        XCTAssertEqual(controller.failure?.text(language:.japanese),AppStrings.text(key,language:.japanese))
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }
}
