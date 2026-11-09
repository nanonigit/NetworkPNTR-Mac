import XCTest
@testable import ArtexCore

final class CoreTests: XCTestCase {
    func testCompleteBrowserInventoryIsPreserved() throws {
        let catalog = try FeatureCatalog.load()
        XCTAssertEqual(catalog.baseline, "e75ae371ad777ffd1eecdd28d2781a6519b05591")
        XCTAssertEqual(catalog.features.count, 21)
        XCTAssertEqual(catalog.routes.count, 27)
        XCTAssertEqual(catalog.endpoints.count, 243)
        XCTAssertEqual(Set(catalog.features.map(\.id)).count, 21)
        XCTAssertEqual(catalog.features.first?.id, "dashboard")
        XCTAssertEqual(catalog.features.last?.id, "settings")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "llm" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "dashboard" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "chat" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "tasks" })?.nativeStatus,"in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "findings" })?.nativeStatus,"in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "traffic" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "agents" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "commands" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "llm-records" })?.nativeStatus, "in_progress")
        XCTAssertEqual(catalog.features.first(where: { $0.id == "assets" })?.nativeStatus, "in_progress")
        XCTAssertTrue(catalog.features.filter { !["llm", "dashboard", "chat", "tasks", "findings", "traffic", "agents", "commands", "llm-records", "assets"].contains($0.id) }.allSatisfy { $0.nativeStatus == "pending" })
    }
    func testLifecycleRejectsDuplicateStartAndPrematureReady() throws {
        var state = LifecycleState.idle
        XCTAssertThrowsError(try state.transition(to: .running))
        try state.transition(to: .starting)
        XCTAssertThrowsError(try state.transition(to: .starting))
        try state.transition(to: .running)
        XCTAssertFalse(state.canStart)
        try state.transition(to: .stopping)
        try state.transition(to: .stopped)
        XCTAssertTrue(state.canStart)
        try state.transition(to: .starting)
        try state.transition(to: .failed)
        XCTAssertTrue(state.canStart)
    }
    func testIntegrityRefusesTamperingAndPathTraversal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("guest".utf8)
        try data.write(to: dir.appendingPathComponent("kernel"))
        let digest = ArtifactIntegrity.sha256(data)
        XCTAssertNoThrow(try ArtifactIntegrity.verify(name: "kernel", expected: digest, directory: dir))
        XCTAssertThrowsError(try ArtifactIntegrity.verify(name: "kernel", expected: String(repeating: "0", count: 64), directory: dir))
        XCTAssertThrowsError(try ArtifactIntegrity.verify(name: "../kernel", expected: digest, directory: dir))
        XCTAssertThrowsError(try ArtifactIntegrity.verify(name: "/kernel", expected: digest, directory: dir))
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("link").path, withDestinationPath: "/etc/passwd")
        XCTAssertThrowsError(try ArtifactIntegrity.verify(name: "link", expected: digest, directory: dir))
    }
    func testConfigurationHasNoHostSharesNetworkingOrDisks() throws {
        let config = try VMConfiguration.make(kernel: URL(fileURLWithPath: "/tmp/kernel"), initramfs: URL(fileURLWithPath: "/tmp/initramfs"), input: nil, output: FileHandle.standardOutput)
        XCTAssertEqual(config.networkDevices.count, 0)
        XCTAssertEqual(config.directorySharingDevices.count, 0)
        XCTAssertEqual(config.storageDevices.count, 0)
        XCTAssertEqual(config.socketDevices.count, 0)
        XCTAssertEqual(config.cpuCount, 2)
    }
}
