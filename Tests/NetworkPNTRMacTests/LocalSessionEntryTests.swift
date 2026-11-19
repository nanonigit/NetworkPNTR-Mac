import Foundation
import XCTest
import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor final class LocalSessionEntryTests: XCTestCase {
    func testOrdinaryLaunchUsesAutomaticSessionWithoutDiagnosticFlags() {
        XCTAssertTrue(RuntimeFactory.usesAutomaticSession(diagnostics: nil, arguments: ["NetworkPNTRMac"]))
    }
    func testExplicitLegacyComparisonKeepsItsIndependentManualContract() {
        let directory = URL(fileURLWithPath: "/private/tmp/owned-comparison")
        XCTAssertFalse(RuntimeFactory.usesAutomaticSession(diagnostics: directory, arguments: ["NetworkPNTRMac", "--native-diagnostics", directory.path]))
        XCTAssertTrue(RuntimeFactory.usesAutomaticSession(diagnostics: directory, arguments: ["NetworkPNTRMac", "--native-diagnostics", directory.path, "--local-session-diagnostics"]))
    }
    func testDirectCloudBundleLaunchKeepsItsCloudRuntimeWithoutArguments() throws {
        XCTAssertTrue(try RuntimeFactory.usesCloudRuntime(bundleVariant: "cloud-preview", diagnostics: nil, arguments: ["NetworkPNTRMac"]))
        XCTAssertFalse(try RuntimeFactory.usesCloudRuntime(bundleVariant: "default", diagnostics: nil, arguments: ["NetworkPNTRMac"]))
        XCTAssertTrue(try RuntimeFactory.usesCloudRuntime(bundleVariant: nil, diagnostics: nil, arguments: ["NetworkPNTRMac", "--cloud-egress"]))
        XCTAssertFalse(try RuntimeFactory.usesCloudRuntime(bundleVariant: "cloud-preview", diagnostics: URL(fileURLWithPath: "/private/tmp/owned-review"), arguments: ["NetworkPNTRMac", "--cloud-egress"]))
        XCTAssertThrowsError(try RuntimeFactory.usesCloudRuntime(bundleVariant: true, diagnostics: nil, arguments: ["NetworkPNTRMac"]))
        XCTAssertThrowsError(try RuntimeFactory.usesCloudRuntime(bundleVariant: "unknown", diagnostics: nil, arguments: ["NetworkPNTRMac"]))
    }

    func testInvalidBundleConfigurationCannotTouchStateOrStartVM() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runtime = DesktopRuntime(artifacts: root.appendingPathComponent("unused"), paths: ManagedRuntimePaths(root: root),
            vault: EphemeralSessionVault(), automaticLocalSession: true, configurationFailure: .integrity("runtime variant"))
        await runtime.start()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(runtime.controller.hasMachine)
        XCTAssertNotNil(runtime.failure)
        XCTAssertNil(runtime.authentication)
    }

    func testCloudPreferenceMigrationCopiesOnlyValidatedLanguageAndNeverOverwrites() throws {
        let oldName = UUID().uuidString, newName = UUID().uuidString
        let legacy = try XCTUnwrap(UserDefaults(suiteName: oldName)), defaults = try XCTUnwrap(UserDefaults(suiteName: newName))
        defer { legacy.removePersistentDomain(forName: oldName); defaults.removePersistentDomain(forName: newName) }
        legacy.set("ja", forKey: AppLanguagePreferences.key)
        legacy.set("fixture-not-copied", forKey: "unrelated-setting")
        RuntimeFactory.migrateCloudLanguagePreference(bundleIdentifier: RuntimeFactory.cloudBundleIdentifier, defaults: defaults, legacy: legacy)
        XCTAssertEqual(defaults.string(forKey: AppLanguagePreferences.key), "ja")
        XCTAssertNil(defaults.object(forKey: "unrelated-setting"))
        defaults.set("en", forKey: AppLanguagePreferences.key)
        RuntimeFactory.migrateCloudLanguagePreference(bundleIdentifier: RuntimeFactory.cloudBundleIdentifier, defaults: defaults, legacy: legacy)
        XCTAssertEqual(defaults.string(forKey: AppLanguagePreferences.key), "en")
        defaults.removeObject(forKey: AppLanguagePreferences.key)
        legacy.set("unsupported", forKey: AppLanguagePreferences.key)
        RuntimeFactory.migrateCloudLanguagePreference(bundleIdentifier: RuntimeFactory.cloudBundleIdentifier, defaults: defaults, legacy: legacy)
        XCTAssertNil(defaults.object(forKey: AppLanguagePreferences.key))
    }

}
