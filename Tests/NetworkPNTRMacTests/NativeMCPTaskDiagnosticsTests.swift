#if DEBUG
import Foundation
import XCTest
@testable import NetworkPNTRMac

final class NativeMCPTaskDiagnosticsTests: XCTestCase {
    func testOwnedDirectorySurvivesCreationAndDirectoryURLHint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let before = URL(fileURLWithPath: root.path, isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let after = URL(fileURLWithPath: root.path, isDirectory: true)
        XCTAssertNotEqual(before, after, "Negative control: URL representation equality does not establish directory identity")
        XCTAssertTrue(NativeMCPTaskDiagnostics.owns(directory: before, requested: after))
        XCTAssertTrue(NativeMCPTaskDiagnostics.owns(directory: after, requested: before))
    }

    func testNoRequestDifferentDirectoryAndNonfileURLAreRejected() {
        let path = URL(fileURLWithPath: "/private/tmp/networkpntr-owned-test", isDirectory: true)
        XCTAssertFalse(NativeMCPTaskDiagnostics.owns(directory: path, requested: nil))
        XCTAssertFalse(NativeMCPTaskDiagnostics.owns(directory: path.appendingPathComponent("other"), requested: path))
        XCTAssertFalse(NativeMCPTaskDiagnostics.owns(directory: URL(string: "https://example.invalid/private/tmp/networkpntr-owned-test")!, requested: path))
    }
}
#endif
