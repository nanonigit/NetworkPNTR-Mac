import XCTest
@testable import NetworkPNTRCore

final class RuntimePathTests: XCTestCase {
    func testManagedPathsArePrivateAndRejectSymlinksOrOpenPermissions() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("state")
        let paths = ManagedRuntimePaths(root: root)
        try paths.prepareDirectories()
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        XCTAssertThrowsError(try paths.prepareDirectories())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try ManagedRuntimePaths(root: link).prepareDirectories())
    }
}
